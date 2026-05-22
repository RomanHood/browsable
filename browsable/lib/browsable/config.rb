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

    attr_reader :root, :data, :config_file, :detected_policy

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
      @detected_policy = detect_allow_browser_policy
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

    # True when an explicit config file was found and loaded.
    def file_present? = !config_file.nil?

    private

    # Read the `allow_browser`/`allow_browsers` policy from the host app's
    # ApplicationController.
    #
    # The spec's ideal is to boot a minimal Rails environment and read the
    # resolved policy. That is slow and fragile (load-order, version skew), so
    # v0.1 statically parses application_controller.rb instead — fast, robust,
    # and accurate for the forms developers actually write.
    #
    # Returns one of:
    #   * a Symbol  — a named policy, e.g. :modern
    #   * a Hash    — an explicit { browser => "version" } map
    #   * nil       — no (uncommented) allow_browser call was found
    #
    # Comments are stripped before matching: a developer who comments the
    # policy out has deliberately disabled it, and browsable must not
    # resurrect it. The whole file is read at once because a versions hash
    # may span several lines.
    # TODO(v0.2): optionally boot Rails for a fully-resolved policy.
    def detect_allow_browser_policy
      controller = File.join(root, "app/controllers/application_controller.rb")
      return nil unless File.file?(controller)

      code = File.read(controller).gsub(/#[^\n]*/, "") # drop every comment
      return nil unless code.match?(/\ballow_browsers?\b/)

      call = code[/\ballow_browsers?\b.*/m]

      if (match = call.match(/versions:\s*\{([^{}]*)\}/m))
        parse_versions_hash(match[1])                      # versions: { ... }
      elsif (match = call.match(/versions:\s*:(\w+)/))
        match[1].to_sym                                    # versions: :modern
      elsif (match = call.match(/\Aallow_browsers?\s+:(\w+)/))
        match[1].to_sym                                    # allow_browsers :modern
      end
    rescue StandardError
      nil
    end

    # Parse the body of a Rails `allow_browser versions: { ... }` hash into a
    # { "browser" => "version" } map.
    #
    # A browser mapped to `false` (blocked) or `true` (any version) carries no
    # version floor, so it is left out of the target entirely — there is
    # nothing to check a numeric requirement against.
    def parse_versions_hash(body)
      versions = {}
      body.scan(/(\w+)\s*:\s*([0-9][0-9.]*|true|false)/) do |browser, value|
        next unless value.match?(/\A[0-9]/)

        versions[browser] = value
      end
      versions.empty? ? nil : versions
    end
  end
end
