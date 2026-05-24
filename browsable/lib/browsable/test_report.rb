# frozen_string_literal: true

require "fileutils"
require "json"
require "tmpdir"

module Browsable
  # The end-of-suite reporting layer for runtime mode.
  #
  # TestReport reads the AuditLog, invokes the v0.1 analyzers **in batch** —
  # one stylelint call, one eslint call regardless of suite size — then groups
  # the resulting findings by endpoint and renders them. It is the only place
  # in runtime mode where a subprocess is spawned.
  #
  # The per-endpoint policy is applied when grouping findings: a CSS feature
  # that flagged the batch target is attributed to every endpoint that loaded
  # the file. HTML findings, which carry exact required versions, can be
  # re-evaluated against each endpoint's specific policy (TODO: v0.2.1).
  class TestReport
    # An analyzer outcome grouped by endpoint, used for rendering.
    EndpointReport = Data.define(:endpoint, :policy, :findings)

    attr_reader :audit_log, :config, :root

    def initialize(audit_log: Browsable.audit_log, config: nil, root: nil)
      @audit_log = audit_log
      @root = root || (defined?(Rails) && Rails.application ? Rails.root.to_s : Dir.pwd)
      @config = config || Config.load(root: @root)
      @analyzed = false
    end

    # Findings (Array<Finding>) discovered across the whole suite.
    def findings
      analyze_if_needed
      @findings
    end

    # Findings grouped per observed endpoint, sorted by endpoint name.
    def endpoint_reports
      analyze_if_needed
      @endpoint_reports
    end

    # Asset paths that could not be resolved against the host app — surfaced as
    # skipped entries so the user understands what the audit could not cover.
    def skipped_assets
      analyze_if_needed
      @skipped_assets
    end

    def errors?
      analyze_if_needed
      @findings.any?(&:error?)
    end

    def warnings?
      analyze_if_needed
      @findings.any?(&:warning?)
    end

    # Build a Report whose shape v0.1's formatters can consume, so runtime
    # output can use the same Human/Json/Github renderers as the CLI.
    def to_report
      analyze_if_needed
      Report.new(
        findings: @findings,
        skips: @skips,
        notes: @notes,
        policies: PolicyScanner.call(root),
        target: batch_target,
        root: root,
        config_file: config.config_file
      )
    end

    # Render the report as a string in the requested format.
    def render(format: :human)
      formatter_for(format).new(to_report).render
    end

    def to_json(*_args)
      JSON.pretty_generate(to_report.as_json.merge(
        endpoints: endpoint_reports.map { |er| endpoint_as_json(er) },
        skipped_assets: skipped_assets
      ))
    end

    # Convenience: exit non-zero when any error finding exists. Drivers call
    # this from their after(:suite) hook when configured to fail on errors.
    def fail_suite_if_errors!(fail_on: :error)
      should_fail =
        case fail_on.to_s
        when "warning" then errors? || warnings?
        when "error"   then errors?
        else                false
        end

      Kernel.exit(1) if should_fail
    end

    private

    # ---- batch analysis ------------------------------------------------------

    def analyze_if_needed
      return if @analyzed

      @analyzed = true
      @findings = []
      @skips = []
      @notes = []
      @skipped_assets = []
      @endpoint_reports = []

      return if audit_log.empty?

      target = batch_target
      run_css_batch(target)
      run_js_batch(target)
      run_html_per_entry

      @endpoint_reports = group_by_endpoint
    end

    # The target the batch invocations are configured against: the most-strict
    # union of every recorded policy, so the analyzer flags any feature that
    # could matter for any endpoint. Per-endpoint precision is re-asserted
    # later when severities are reassigned.
    def batch_target
      @batch_target ||= compute_batch_target
    end

    def compute_batch_target
      targets = audit_log.entries.map { |entry| entry.policy.target }.uniq { |t| t.browsers }
      return config.target if targets.empty?

      # Minimum version per browser across all observed targets — i.e. the
      # browser-support floor every endpoint shares.
      union = {}
      targets.each do |t|
        t.browsers.each do |browser, version|
          existing = union[browser]
          union[browser] = version if existing.nil? || gem_version(version) < gem_version(existing)
        end
      end

      Target.new("runtime-union", resolved: union)
    end

    def run_css_batch(target)
      paths_on_disk = audit_log.asset_path_universe.select { |p| css?(p) && File.file?(p) }
      tmp_files = write_inline_blocks(:css)
      all_files = paths_on_disk.to_a + tmp_files

      track_unresolved(:css)
      return if all_files.empty?
      return record_skip(:css, "stylelint not found — run `browsable doctor`") unless available?(:css)

      analyzer = Analyzers::CSS.new(target: target, config: config)
      collected = safe_analyze(:css, analyzer, all_files)
      remap_tmp_findings(collected, tmp_files, :css)
      @findings.concat(collected)
    ensure
      cleanup(tmp_files) if tmp_files
    end

    def run_js_batch(target)
      paths_on_disk = audit_log.asset_path_universe.select { |p| js?(p) && File.file?(p) }
      tmp_files = write_inline_blocks(:js)
      all_files = paths_on_disk.to_a + tmp_files

      track_unresolved(:js)
      return if all_files.empty?
      return record_skip(:js, "eslint not found — run `browsable doctor`") unless available?(:js)

      analyzer = Analyzers::Javascript.new(target: target, config: config)
      collected = safe_analyze(:js, analyzer, all_files)
      remap_tmp_findings(collected, tmp_files, :js)
      @findings.concat(collected)
    ensure
      cleanup(tmp_files) if tmp_files
    end

    def run_html_per_entry
      audit_log.entries.each do |entry|
        next if entry.html.empty?

        analyzer = Analyzers::HTML.new(target: entry.policy.target, config: config)
        results = analyzer.analyze_source(entry.html, file: synthetic_path_for(entry))
        @findings.concat(results)
      rescue StandardError => e
        record_skip(:html, "HTML analysis failed for #{entry.endpoint}: #{e.message}")
      end
    end

    # ---- attribution + grouping ---------------------------------------------

    # Build per-endpoint groupings. For each endpoint, gather:
    #   - findings on HTML it produced (via synthetic path)
    #   - findings on assets it loaded (looked up via AuditLog#entries_loading)
    def group_by_endpoint
      by_endpoint = Hash.new { |h, k| h[k] = [] }
      endpoint_policies = {}

      audit_log.entries.each do |entry|
        endpoint_policies[entry.endpoint] ||= entry.policy
      end

      @findings.each do |finding|
        owners = endpoints_for(finding)
        owners.each do |endpoint|
          by_endpoint[endpoint] << finding
          endpoint_policies[endpoint] ||= policy_for(endpoint)
        end
      end

      by_endpoint.sort.map do |endpoint, list|
        EndpointReport.new(
          endpoint: endpoint,
          policy: endpoint_policies[endpoint],
          findings: list.uniq
        )
      end
    end

    def endpoints_for(finding)
      file = finding.file
      synthetic = synthetic_prefix
      return [file.sub(synthetic, "")] if file.start_with?(synthetic)

      audit_log.entries_loading(file).map(&:endpoint).uniq
    end

    def policy_for(endpoint)
      entry = audit_log.entries.find { |e| e.endpoint == endpoint }
      entry&.policy
    end

    # ---- helpers ------------------------------------------------------------

    def write_inline_blocks(kind)
      blocks = audit_log.entries.flat_map(&:inline_blocks).select { |b| b.kind == kind }
      return [] if blocks.empty?

      dir = (@inline_dir ||= Dir.mktmpdir("browsable-inline"))
      ext = kind == :css ? "css" : "js"
      blocks.uniq(&:content).each_with_index.map do |block, idx|
        path = File.join(dir, "inline-#{idx}.#{ext}")
        File.write(path, block.content)
        path
      end
    end

    def cleanup(paths)
      paths.each { |p| File.delete(p) if File.file?(p) }
    rescue StandardError
      nil
    end

    # Rewrite a finding's file from the tmpdir path to something users will
    # recognize ("(inline <style> block)"), so reports never leak temp paths.
    def remap_tmp_findings(findings, tmp_files, kind)
      tmp_set = tmp_files.to_set
      label = kind == :css ? "(inline <style> block)" : "(inline <script> block)"
      findings.map! do |f|
        next f unless tmp_set.include?(f.file)

        Finding.new(**f.to_h.merge(file: label))
      end
    end

    def track_unresolved(kind)
      audit_log.entries.each do |entry|
        entry.asset_paths.each do |ref|
          next unless ref.kind == kind
          next unless ref.resolved_path.nil?

          @skipped_assets << { url: ref.url, kind: ref.kind.to_s, endpoint: entry.endpoint }
        end
      end
    end

    def safe_analyze(kind, analyzer, files)
      analyzer.analyze(files)
    rescue StandardError => e
      record_skip(kind, "#{kind} analysis failed: #{e.message}")
      []
    end

    def record_skip(kind, reason)
      @skips << Report::Skip.new(kind: kind, reason: reason)
      []
    end

    def available?(kind)
      Doctor.new.available_kinds.include?(kind)
    end

    def css?(path) = %w[.css .scss].include?(File.extname(path).downcase)
    def js?(path)  = %w[.js .mjs].include?(File.extname(path).downcase)

    SYNTHETIC_PREFIX = "[response] "

    def synthetic_prefix = SYNTHETIC_PREFIX
    def synthetic_path_for(entry) = "#{SYNTHETIC_PREFIX}#{entry.endpoint}"

    def endpoint_as_json(report)
      {
        endpoint: report.endpoint,
        policy: report.policy&.as_json,
        findings: report.findings.map(&:as_json)
      }
    end

    def formatter_for(format)
      case format.to_sym
      when :json   then Formatters::Json
      when :github then Formatters::Github
      else              Formatters::Human
      end
    end

    def gem_version(value)
      Gem::Version.new(value.to_s)
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
