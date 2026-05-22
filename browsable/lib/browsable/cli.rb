# frozen_string_literal: true

require "thor"
require "json"
require "erb"
require "pastel"

module Browsable
  # The `browsable` command-line interface.
  #
  # CLI is a thin shell: it parses flags, runs the audit pipeline (sources →
  # analyzers → report), and hands the Report to a formatter. Every command's
  # real logic lives in the classes it orchestrates.
  class CLI < Thor
    # The analyzer used for each routed file kind.
    ANALYZERS = {
      css:  Analyzers::CSS,
      erb:  Analyzers::ERB,
      html: Analyzers::HTML,
      js:   Analyzers::Javascript
    }.freeze

    SKIP_REASONS = {
      css: "stylelint not found — run `browsable doctor`",
      js:  "eslint / eslint-plugin-compat not found — run `browsable doctor`"
    }.freeze

    def self.exit_on_failure? = true

    class_option :config, type: :string, aliases: "-c", desc: "Path to a config file"
    class_option :format, type: :string, enum: %w[human json github], desc: "Output format"
    class_option :json, type: :boolean, desc: "Shortcut for --format json"

    desc "audit [PATH]", "Audit a Rails app's frontend for browser-compatibility issues"
    long_desc <<~DESC
      Discovers the project's CSS, ERB/HTML and JavaScript, audits each against
      the browser-support target inferred from ApplicationController's
      allow_browser policy, and reports what your code requires versus what your
      policy permits. Runs with zero configuration.
    DESC
    option :target, type: :string, desc: "Override the inferred browserslist query"
    option :"no-build", type: :boolean, default: false,
                        desc: "Scan only what is on disk (browsable never builds assets itself)"
    option :include, type: :array, default: [], desc: "Extra path globs to scan (repeatable)"
    option :exclude, type: :array, default: [], desc: "Path globs to exclude (repeatable)"
    option :"fail-on", type: :string, enum: %w[warning error], default: "error",
                       desc: "Exit non-zero when a finding of this severity (or higher) exists"
    def audit(path = ".")
      root = File.expand_path(path)
      config = load_config(root)
      target = resolve_target(config)

      warn_missing_dependencies
      report = run_audit(root: root, config: config, target: target)
      emit(report)
      exit(report.exit_code(fail_on: options["fail-on"] || "error"))
    end
    default_command :audit

    desc "doctor", "Check that browsable's system dependencies are installed"
    option :fix, type: :boolean, default: false,
                 desc: "Attempt to install missing dependencies via brew/npm"
    def doctor
      doc = Doctor.new
      puts doc.render(color: color?)

      if options[:fix] && !doc.ok?
        puts
        doc.fix!
        puts
        puts doc.render(color: color?)
      end

      exit(doc.ok? ? 0 : 1)
    end

    desc "check FILE [FILE...]", "Audit specific files (used by editor integrations)"
    option :target, type: :string, desc: "Override the inferred browserslist query"
    def check(*files)
      abort_with("`check` needs at least one file path.") if files.empty?

      paths = files.map { |file| File.expand_path(file) }
      root = detect_root(paths.first)
      config = load_config(root)
      target = resolve_target(config)

      report = run_audit(root: root, config: config, target: target, file_list: paths)
      emit(report)
      exit(report.exit_code(fail_on: "error"))
    end

    desc "init", "Generate a .browsable.yml in the current directory"
    long_desc <<~DESC
      Writes a fully-commented .browsable.yml. Rails users should prefer the
      generator: `rails g browsable:install` (writes config/browsable.yml).
    DESC
    option :force, type: :boolean, default: false, desc: "Overwrite an existing file"
    option :minimal, type: :boolean, default: false, desc: "Write section headers only"
    option :target, type: :string, desc: "Pre-populate a manual target query"
    def init
      destination = File.expand_path(".browsable.yml")
      if File.exist?(destination) && !options[:force]
        abort_with("#{destination} already exists. Pass --force to overwrite.")
      end

      File.write(destination, render_config_template)
      puts pastel.green("Created #{destination}")
      puts pastel.dim("This file is optional — delete it and browsable still works. " \
                      "Uncomment a line to override a default.")
      puts pastel.dim("Run `browsable audit` to try it out.")
    end

    desc "target [PATH]", "Show the browser-support target browsable inferred"
    def target(path = ".")
      config = load_config(File.expand_path(path))
      resolved = resolve_target(config)

      if json_output?
        puts JSON.pretty_generate(resolved.as_json)
      else
        puts pastel.bold("Target: #{resolved.query}")
        resolved.browsers.each { |browser, version| puts "  #{browser} >= #{version}" }
      end
    end

    desc "version", "Print the browsable version"
    def version
      puts "browsable #{Browsable::VERSION}"
    end
    map %w[--version -v] => :version

    private

    # --- pipeline ------------------------------------------------------------

    def run_audit(root:, config:, target:, file_list: nil)
      available = Doctor.new.available_kinds
      skips = []
      files_by_kind = file_list ? route_files(file_list) : discover_files(root: root, config: config)

      collect_importmap(root: root, config: config, files_by_kind: files_by_kind, skips: skips) if file_list.nil?

      findings = []
      ANALYZERS.each do |kind, analyzer_class|
        files = files_by_kind[kind] || []
        next if files.empty?

        unless available.include?(kind)
          skips << Report::Skip.new(kind: kind, reason: SKIP_REASONS.fetch(kind, "tooling unavailable"))
          next
        end

        analyzer = analyzer_class.new(target: target, config: config)
        findings.concat(analyzer.analyze(files))
      rescue StandardError => e
        skips << Report::Skip.new(kind: kind, reason: "#{kind} analysis failed: #{e.message}")
      end

      Report.new(findings: findings, skips: skips, target: target,
                 root: root, config_file: config.config_file)
    end

    def collect_importmap(root:, config:, files_by_kind:, skips:)
      return unless config.importmap_enabled?

      importmap = Sources::Importmap.new(root: root)
      return unless importmap.present?

      if ENV["BROWSABLE_OFFLINE"] == "1"
        skips << Report::Skip.new(kind: :importmap,
                                  reason: "BROWSABLE_OFFLINE=1 — remote pins were not fetched")
        return
      end

      (files_by_kind[:js] ||= []).concat(importmap.fetch)
    end

    def discover_files(root:, config:)
      src = config.sources
      excludes = Array(options[:exclude]) + config.ignore_files

      sources = [
        Sources::Stylesheets.new(root: root, globs: src["stylesheets"], excludes: excludes),
        Sources::Builds.new(root: root, globs: src["builds"], excludes: excludes),
        Sources::Views.new(root: root, globs: src["views"], excludes: excludes),
        Sources::Javascripts.new(root: root, globs: src["javascript"], excludes: excludes),
        Sources::PublicAssets.new(root: root, globs: src["public"], excludes: excludes)
      ]

      extra = Array(src["custom"]) + Array(options[:include])
      sources << Sources::Base.new(root: root, globs: extra, excludes: excludes) if extra.any?

      route_files(sources.flat_map(&:files).uniq)
    end

    # Route files to an analyzer by extension. `*.html.erb` ends in `.erb`.
    def route_files(files)
      buckets = { css: [], erb: [], html: [], js: [] }
      files.each do |file|
        case File.extname(file).downcase
        when ".css", ".scss" then buckets[:css] << file
        when ".js", ".mjs"   then buckets[:js] << file
        when ".erb"          then buckets[:erb] << file
        when ".html", ".htm" then buckets[:html] << file
        end
        # TODO(v0.2): route Ruby view components (app/components/**/*.rb).
      end
      buckets
    end

    # --- output --------------------------------------------------------------

    def emit(report)
      puts formatter_class.new(report).render
    end

    def formatter_class
      name = json_output? ? "json" : (options[:format] || "human")
      { "human" => Formatters::Human, "json" => Formatters::Json,
        "github" => Formatters::Github }.fetch(name)
    end

    def json_output?
      options[:json] || options[:format] == "json"
    end

    # --- config / target ----------------------------------------------------

    def load_config(root)
      Config.load(root: root, path: options[:config])
    rescue ConfigError => e
      abort_with(e.message)
    end

    def resolve_target(config)
      options[:target] ? Target.new(options[:target]) : config.target
    end

    # --- helpers -------------------------------------------------------------

    def warn_missing_dependencies
      return if ENV.key?("BROWSABLE_DRY_RUN")

      missing = %i[css js] - Doctor.new.available_kinds
      return if missing.empty?

      $stderr.puts pastel(io: $stderr).yellow(
        "! #{missing.join(' and ')} analysis is disabled (missing tools). " \
        "Run `browsable doctor` for setup instructions."
      )
    end

    # Walk up from a file to find the project root.
    def detect_root(start)
      dir = File.directory?(start) ? start : File.dirname(start)
      markers = %w[Gemfile config.ru .browsable.yml config/browsable.yml]
      current = dir
      loop do
        return current if markers.any? { |m| File.exist?(File.join(current, m)) }

        parent = File.dirname(current)
        return dir if parent == current

        current = parent
      end
    end

    def render_config_template
      template_path = File.expand_path(
        "../generators/browsable/install/templates/browsable.yml.tt", __dir__
      )
      policy = Config.load(root: Dir.pwd).detected_policy
      comment =
        if policy
          "# Detected: ApplicationController uses `allow_browser versions: :#{policy}`"
        else
          "# (No allow_browser call detected — browsable will fall back to browserslist defaults.)"
        end

      ERB.new(File.read(template_path), trim_mode: "-")
         .result_with_hash(detected_comment: comment,
                           manual_query: options[:target],
                           minimal: options[:minimal])
    end

    def color?
      $stdout.tty?
    end

    def pastel(io: $stdout)
      Pastel.new(enabled: io.tty?)
    end

    def abort_with(message)
      $stderr.puts pastel(io: $stderr).red("Error: #{message}")
      exit(1)
    end
  end
end
