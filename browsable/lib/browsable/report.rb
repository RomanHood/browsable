# frozen_string_literal: true

module Browsable
  # The aggregated result of an audit: every Finding produced by every
  # analyzer, plus a record of any analyzer or source that was skipped.
  #
  # A Report makes no decisions. It tells the user what their code requires and
  # how that compares against their target; the formatters present it and the
  # exit-code policy lives entirely in the caller's chosen --fail-on value.
  class Report
    # A skipped unit of work, e.g. { kind: :css, reason: "stylelint missing" }.
    Skip = Data.define(:kind, :reason)

    # A suggested allow_browser line that would resolve the below-target errors.
    # `bumps` maps each raised browser to { from:, to: }.
    Suggestion = Data.define(:line, :bumps)

    attr_reader :findings, :skips, :notes, :target, :root, :config_file

    # @param notes [Array<String>] caveats about the run itself (e.g. a target
    #   that could not be inferred) — distinct from per-file findings.
    def initialize(findings: [], skips: [], notes: [], target: nil, root: nil, config_file: nil)
      @findings = findings
      @skips = skips
      @notes = notes
      @target = target
      @root = root
      @config_file = config_file
    end

    def errors   = findings.select(&:error?)
    def warnings = findings.select(&:warning?)
    def infos    = findings.select(&:info?)

    def empty? = findings.empty?

    # Findings grouped by file path, files sorted, findings sorted by position.
    def findings_by_file
      findings
        .group_by(&:file)
        .sort_by(&:first)
        .to_h
        .transform_values { |group| group.sort_by { |f| [f.line, f.column] } }
    end

    # Exit code implementing the --fail-on policy.
    def exit_code(fail_on:)
      case fail_on.to_s
      when "warning"
        errors.any? || warnings.any? ? 1 : 0
      when "error"
        errors.any? ? 1 : 0
      else
        0
      end
    end

    # An allow_browser line that raises the offending browsers just enough to
    # cover every below-target error, leaving the other browsers untouched.
    #
    # Returns nil when no error carries comparable version data — CSS/JS
    # findings come from stylelint/eslint, which do not expose exact versions,
    # so a suggestion can only be derived from HTML/ERB findings.
    def suggestion
      return @suggestion if defined?(@suggestion)

      @suggestion = build_suggestion
    end

    def as_json
      {
        target: target&.as_json,
        notes: notes,
        summary: {
          errors: errors.size,
          warnings: warnings.size,
          infos: infos.size,
          files: findings_by_file.size
        },
        findings: findings.map(&:as_json),
        skips: skips.map { |skip| { kind: skip.kind.to_s, reason: skip.reason } },
        suggested_policy: suggestion && { line: suggestion.line, bumps: suggestion.bumps }
      }
    end

    private

    def build_suggestion
      return nil unless target

      # The highest version each browser must reach to clear every error that
      # offends it. A finding only contributes where required > current floor.
      bumps = {}
      errors.each do |finding|
        finding.required_browser_versions.each do |browser, required|
          floor = finding.target_browser_versions[browser]
          next unless floor && newer?(required, floor)

          bumps[browser] = required if bumps[browser].nil? || newer?(required, bumps[browser])
        end
      end
      return nil if bumps.empty?

      # Start from the current target and raise only the offending browsers.
      versions = target.browsers.dup
      detail = {}
      bumps.each do |browser, raised_to|
        detail[browser] = { from: versions[browser], to: raised_to }
        versions[browser] = raised_to
      end

      pairs = versions.map { |browser, version| "#{browser}: #{version}" }
      Suggestion.new(line: "allow_browser versions: { #{pairs.join(', ')} }", bumps: detail)
    end

    def newer?(left, right)
      Gem::Version.new(left.to_s) > Gem::Version.new(right.to_s)
    rescue ArgumentError
      false
    end
  end
end
