# frozen_string_literal: true

module Browsable
  # Identifies which Rails asset pipeline (Propshaft, Sprockets, both, or
  # neither) is in use for a project. Reported in the audit header so the user
  # sees at a glance which pipeline browsable inferred — and surfaced in the
  # JSON output so editor integrations and CI can branch on it.
  #
  # Detection prefers a live `defined?` check (set when running inside the host
  # Rails process, e.g. via the railtie or a rake task). Standalone CLI runs
  # never load the host app, so the fallback inspects the project's
  # Gemfile.lock — the canonical record of which asset-pipeline gem the app
  # actually uses.
  class AssetPipeline
    PROPSHAFT = "propshaft"
    SPROCKETS = "sprockets"
    BOTH      = "sprockets+propshaft"
    NONE      = "none"

    # Build a pipeline descriptor for the project at `root`.
    def self.detect(root:)
      new(root: root)
    end

    attr_reader :root

    def initialize(root:)
      @root = File.expand_path(root)
    end

    # One of PROPSHAFT, SPROCKETS, BOTH, NONE.
    def name
      @name ||= identify
    end

    def propshaft? = name == PROPSHAFT || name == BOTH
    def sprockets? = name == SPROCKETS || name == BOTH
    def none?      = name == NONE

    # When both pipelines are loaded (typical during a Propshaft migration),
    # prefer Sprockets-style discovery — its source tree is the broader
    # superset, so its globs match everything Propshaft would have found too.
    def prefer_sprockets_layout? = sprockets?

    private

    def identify
      live_propshaft = defined?(::Propshaft) ? true : false
      live_sprockets = defined?(::Sprockets) ? true : false

      # Live `defined?` is authoritative — the host app actually loaded these.
      return BOTH      if live_propshaft && live_sprockets
      return PROPSHAFT if live_propshaft
      return SPROCKETS if live_sprockets

      # Standalone CLI mode: fall back to what the Gemfile.lock declares.
      lock_propshaft = gemfile_lock_mentions?("propshaft")
      lock_sprockets = gemfile_lock_mentions?("sprockets-rails") ||
                       gemfile_lock_mentions?("sprockets")

      return BOTH      if lock_propshaft && lock_sprockets
      return PROPSHAFT if lock_propshaft
      return SPROCKETS if lock_sprockets

      NONE
    end

    def gemfile_lock_mentions?(gem_name)
      path = File.join(root, "Gemfile.lock")
      return false unless File.file?(path)

      # `bundle` indents direct gem entries with four spaces; transitive deps
      # appear under DEPENDENCIES with two. Either form counts as "in use".
      File.read(path).match?(/^\s+#{Regexp.escape(gem_name)}\b/)
    end
  end
end
