# frozen_string_literal: true

require "open3"

module Browsable
  # A browser-support target: the browsers and minimum versions the project
  # intends to support, expressed as a browserslist query.
  #
  # Target resolves a query into concrete minimum versions. It prefers the
  # `browserslist` CLI (installed alongside node) and falls back to a small
  # built-in table when node is not available.
  class Target
    # Rails 8's `allow_browser versions: :modern` resolves to roughly this set.
    # Mirrors ActionController's modern-browser baseline so browsable can read
    # the policy without booting Rails.
    MODERN = {
      "chrome" => "120", "edge" => "120", "firefox" => "121",
      "safari" => "17.2", "opera" => "106"
    }.freeze

    # browsable's built-in approximation of the browserslist `defaults` query —
    # a frozen snapshot, used only as a last resort when the `browserslist` CLI
    # is not installed (so live caniuse data cannot be queried) and there is no
    # policy or explicit target. #note flags whenever this fallback is in play.
    DEFAULTS = {
      "chrome" => "109", "edge" => "109", "firefox" => "115", "safari" => "15.6"
    }.freeze

    # Maps browserslist's browser codes onto the names browsable reports with.
    BROWSERSLIST_ALIASES = {
      "ios_saf" => "safari", "and_chr" => "chrome", "and_ff" => "firefox",
      "samsung" => "samsung", "op_mob" => "opera"
    }.freeze

    attr_reader :query

    # The Rails `:modern` baseline, fully resolved.
    def self.modern
      new("modern", resolved: MODERN)
    end

    # Build a Target from a Rails `allow_browser versions:` argument.
    def self.from_rails_policy(versions)
      case versions
      when :modern, "modern", nil
        modern
      when Hash
        new("custom allow_browser policy", resolved: normalize_hash(versions))
      else
        # A named policy we don't special-case — treat the name as a query.
        new(versions.to_s)
      end
    end

    def self.normalize_hash(hash)
      hash.each_with_object({}) do |(browser, version), out|
        out[browser.to_s] = version.to_s
      end
    end

    def initialize(query, resolved: nil)
      @query = query
      @resolved = resolved
      # How #browsers was obtained: :explicit (a caller supplied it, e.g. a
      # Rails policy), :browserslist (the CLI), or :builtin (the frozen table).
      @resolved_via = resolved ? :explicit : nil
    end

    # The resolved minimum versions, e.g. { "chrome" => "120", ... }.
    def browsers
      @resolved ||= resolve
    end

    # The minimum supported version of a browser, or nil if untargeted.
    def minimum_version(browser)
      browsers[browser.to_s]
    end

    # True when `version` of `browser` falls within the target.
    def includes?(browser, version)
      min = minimum_version(browser)
      return false unless min && version

      Gem::Version.new(version.to_s) >= Gem::Version.new(min.to_s)
    rescue ArgumentError
      false
    end

    # Format the target as browserslist query fragments, e.g.
    # ["chrome >= 120", "safari >= 17.2"]. Used to configure stylelint/eslint.
    def to_browserslist
      browsers.map { |browser, version| "#{browser} >= #{version}" }
    end

    def to_s = query.to_s

    # How #browsers was resolved: :explicit, :browserslist, or :builtin.
    def resolved_via
      browsers # force resolution
      @resolved_via
    end

    # A caveat about this target's accuracy, or nil. Set when browsable had to
    # fall back to its built-in table instead of querying live browserslist data.
    def note
      return nil unless resolved_via == :builtin
      return nil if query.to_s.strip.downcase == "modern" # the builtin :modern set is exact

      "The versions above are browsable's built-in approximation — the `browserslist` " \
        "CLI is not installed, so live browser-share data could not be queried. Install " \
        "it (npm install -g browserslist) or set an explicit `target:` in " \
        "config/browsable.yml for accurate, stable versions."
    end

    def as_json
      { query: query.to_s, browsers: browsers, resolved_via: resolved_via }
    end

    private

    def resolve
      if (from_cli = from_browserslist_cli)
        @resolved_via = :browserslist
        from_cli
      else
        @resolved_via = :builtin
        builtin_fallback
      end
    end

    # Shell out to the `browserslist` CLI when available. It emits one
    # "<browser> <version>" line per supported version; we keep the lowest.
    def from_browserslist_cli
      stdout, _stderr, status = Open3.capture3("browserslist", query.to_s)
      return nil unless status.success?

      mins = {}
      stdout.each_line do |line|
        code, version = line.strip.split(/\s+/, 2)
        next unless code && version

        name = BROWSERSLIST_ALIASES.fetch(code, code)
        version = version.split("-").first # ranges like "16.0-16.3"
        current = mins[name]
        mins[name] = version if current.nil? || gem_version(version) < gem_version(current)
      end
      mins.empty? ? nil : mins
    rescue Errno::ENOENT
      # `browserslist` is not installed — fall back to the built-in table.
      nil
    end

    # A deliberately small parser for the common queries browsable sees when
    # node is absent. Full browserslist semantics live in the CLI above.
    def builtin_fallback
      q = query.to_s.downcase.strip
      return MODERN.dup if q == "modern"
      return DEFAULTS.dup if q.empty? || q.include?("defaults")

      parsed = {}
      q.split(",").each do |clause|
        if (m = clause.strip.match(/\A(\w[\w ]*?)\s*>=\s*([\d.]+)\z/))
          parsed[m[1].strip] = m[2]
        end
      end
      parsed.empty? ? DEFAULTS.dup : parsed
    end

    def gem_version(value)
      Gem::Version.new(value)
    rescue ArgumentError
      Gem::Version.new("0")
    end
  end
end
