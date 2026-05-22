# frozen_string_literal: true

require "yaml"

module Browsable
  # Resolves the effective configuration for an audit run.
  #
  # browsable runs fully zero-config: when no config file is present every
  # value below is inferred. A config file only exists to *override* defaults.
  #
  # Resolution precedence (highest wins) is applied by the caller:
  #   1. CLI flags        (handled in CLI)
  #   2. config file      (loaded here)
  #   3. inferred Rails   (allow_browser policy, read here)
  #   4. gem defaults     (DEFAULTS below)
  class Config
    DEFAULTS = {
      "target" => {
        "source"       => "allow_browsers", # allow_browsers | browserslist | manual
        "manual_query" => "defaults"
      },
      "sources" => {
        "stylesheets" => ["app/assets/stylesheets/**/*.{css,scss}"],
        "builds"      => ["app/assets/builds/**/*.css"],
        "views"       => ["app/views/**/*.{html.erb,turbo_stream.erb}",
                          "app/components/**/*.{rb,html.erb}"],
        "javascript"  => ["app/javascript/**/*.{js,mjs}"],
        "importmap"   => true,
        "public"      => ["public/**/*.{html,css,js}"],
        "custom"      => []
      },
      "severity" => {
        "baseline_newly_available" => "warning",
        "baseline_limited"         => "error",
        "below_target"             => "error"
      },
      "ignore" => {
        "features" => [],
        "files"    => []
      }
    }.freeze

    # Discovery order for an implicit config file, relative to the project root.
    CONFIG_FILENAMES = ["config/browsable.yml", ".browsable.yml"].freeze

    attr_reader :root, :data, :config_file, :detected_policy, :policy_note

    # Load and merge configuration for a project rooted at `root`.
    #
    # @param root [String] the Rails app (or project) root
    # @param path [String, nil] an explicit config file path (from --config)
    def self.load(root:, path: nil)
      root = File.expand_path(root)
      config_file = locate_file(root, path)
      file_data = config_file ? parse_file(config_file) : {}
      merged = deep_merge(DEFAULTS, file_data)
      new(root: root, data: merged, config_file: config_file)
    end

    def self.locate_file(root, explicit)
      if explicit
        full = File.expand_path(explicit, root)
        raise ConfigError, "Config file not found: #{explicit}" unless File.file?(full)

        return full
      end

      CONFIG_FILENAMES
        .map { |name| File.join(root, name) }
        .find { |candidate| File.file?(candidate) }
    end

    def self.parse_file(path)
      loaded = YAML.safe_load_file(path) || {}
      raise ConfigError, "#{path} must contain a YAML mapping" unless loaded.is_a?(Hash)

      loaded
    rescue Psych::SyntaxError => e
      raise ConfigError, "Could not parse #{path}: #{e.message}"
    end

    def self.deep_merge(base, override)
      base.merge(override) do |_key, base_val, override_val|
        if base_val.is_a?(Hash) && override_val.is_a?(Hash)
          deep_merge(base_val, override_val)
        else
          override_val
        end
      end
    end

    def initialize(root:, data:, config_file: nil)
      @root = root
      @data = data
      @config_file = config_file
      # PolicyDetector statically resolves the Rails allow_browser policy.
      # `policy_note` is set when a call was found but could not be resolved.
      result = PolicyDetector.call(root)
      @detected_policy = result.policy
      @policy_note = result.note
    end

    def sources       = data.fetch("sources")
    def severity      = data.fetch("severity")
    def ignore_features = Array(data.dig("ignore", "features"))
    def ignore_files    = Array(data.dig("ignore", "files"))
    def importmap_enabled? = sources.fetch("importmap", true) != false

    # Resolve the browser-support Target implied by this config.
    def target
      cfg = data.fetch("target")
      case cfg["source"]
      when "manual"
        Target.new(cfg.fetch("manual_query", "defaults"))
      when "browserslist"
        # Defer entirely to the project's browserslist config (.browserslistrc).
        Target.new("defaults")
      else # "allow_browsers" (the default)
        detected_policy ? Target.from_rails_policy(detected_policy) : Target.new("defaults")
      end
    end

    # Major browsers an explicit allow_browser *hash* neither pins to a version
    # nor blocks. Rails allows these at any version — it only ever blocks a
    # browser it was given a minimum (or `false`) for — so browsable has no
    # floor to audit them against. Empty unless the policy is an explicit hash.
    def unconstrained_browsers
      return [] unless detected_policy.is_a?(Hash)

      Target::MODERN.keys - detected_policy.keys
    end

    # Informational caveats about the resolved target. The key one explains how
    # Rails treats browsers absent from an explicit allow_browser hash, so the
    # user is never left guessing what happens to the browsers they omitted.
    def target_notes
      return [] if unconstrained_browsers.empty?

      pinned = detected_policy.keys.join(", ")
      omitted = unconstrained_browsers.join(", ")
      ["Your allow_browser policy pins a version only for #{pinned}. Rails leaves every " \
       "browser you don't list (#{omitted}) allowed at any version, so browsable audits " \
       "only #{pinned}. Add a `target:` block to config/browsable.yml to audit the others."]
    end

    # True when an explicit config file was found and loaded.
    def file_present? = !config_file.nil?
  end
end
