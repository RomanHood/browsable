# frozen_string_literal: true

require "uri"

module Browsable
  # Translates an asset URL discovered in an HTML response into an on-disk file
  # path under the Rails app. Runtime mode hands every <link> / <script src>
  # through here so the end-of-suite analyzers can read those files directly.
  #
  # The resolver is intentionally conservative: it returns `nil` rather than
  # guessing when a URL clearly belongs to a third-party CDN, when the digested
  # filename does not map back to a real source on disk, or when the host Rails
  # app cannot be introspected. The TestReport surfaces those misses as skipped
  # entries — never as fabricated findings.
  class AssetResolver
    # The strategy used to resolve a given URL, exposed for diagnostics.
    Result = Data.define(:path, :strategy) do
      def resolved? = !path.nil?
    end

    DIGEST_PATTERN = /-[0-9a-f]{7,64}(?=\.\w+\z)/.freeze

    DEFAULT_ROOTS = %w[
      app/assets/stylesheets
      app/assets/javascripts
      app/javascript
      app/assets/builds
      vendor/assets/stylesheets
      vendor/assets/javascripts
      public
    ].freeze

    attr_reader :rails_app

    def initialize(rails_app: nil, root: nil, search_roots: nil)
      @rails_app = rails_app || (defined?(Rails) ? Rails.application : nil)
      @root = root && File.expand_path(root)
      @search_roots = search_roots
    end

    # Resolve a URL to an absolute on-disk path. Returns nil for URLs we cannot
    # honestly attribute to a file in the host application.
    def resolve(url)
      detailed_resolve(url).path
    end

    # Same as #resolve, but returns a Result carrying which strategy matched —
    # useful for the benchmark script and for skipped-entry diagnostics.
    def detailed_resolve(url)
      return Result.new(path: nil, strategy: :empty) if url.nil? || url.empty?

      path = path_component(url)
      return Result.new(path: nil, strategy: :external) if path.nil?

      undigested = strip_digest(path)

      if (hit = resolve_via_propshaft(undigested))
        return Result.new(path: hit, strategy: :propshaft)
      end

      if (hit = resolve_via_sprockets(undigested))
        return Result.new(path: hit, strategy: :sprockets)
      end

      if (hit = resolve_via_filesystem(undigested))
        return Result.new(path: hit, strategy: :filesystem)
      end

      if (hit = resolve_via_public(undigested))
        return Result.new(path: hit, strategy: :public)
      end

      Result.new(path: nil, strategy: :unresolved)
    end

    private

    # Reduce a URL to its path component. Returns nil for absolute URLs whose
    # host does not match the application's configured asset host — those are
    # treated as external (CDN-hosted) and skipped.
    #
    # TODO(v0.2.1): handle CDN-hosted absolute URLs that *do* match
    # `config.asset_host`, including digest-only URLs (e.g. a CloudFront prefix
    # that retains the same path layout the Rails app uses).
    def path_component(url)
      uri = URI.parse(url)
      return nil if uri.scheme == "data" || uri.scheme == "javascript"

      if uri.absolute?
        return nil unless matches_asset_host?(uri)

        uri.path
      else
        uri.path
      end
    rescue URI::InvalidURIError
      url.split("?", 2).first
    end

    def matches_asset_host?(uri)
      hosts = configured_asset_hosts
      return false if hosts.empty?

      hosts.any? { |host| host == uri.host || (host.respond_to?(:include?) && host.include?(uri.host.to_s)) }
    end

    def configured_asset_hosts
      return [] unless rails_app

      asset_host = rails_app.config.action_controller.asset_host rescue nil
      Array(asset_host).compact.map do |entry|
        URI.parse(entry).host || entry rescue entry
      end
    end

    def strip_digest(path)
      path.sub(DIGEST_PATTERN, "")
    end

    # --- Propshaft (Rails 7+ default) ---------------------------------------

    def resolve_via_propshaft(path)
      return nil unless rails_app
      return nil unless rails_app.respond_to?(:assets)

      assets = rails_app.assets
      return nil unless assets.respond_to?(:resolver)

      logical = path.sub(%r{\A/assets/}, "").sub(%r{\A/}, "")
      asset = assets.resolver.asset_for(logical) rescue nil
      return nil unless asset

      candidate = asset.respond_to?(:path) ? asset.path.to_s : nil
      return nil unless candidate && File.file?(candidate)

      candidate
    rescue StandardError
      nil
    end

    # --- Sprockets fallback --------------------------------------------------

    def resolve_via_sprockets(path)
      return nil unless rails_app
      assets = rails_app.config.assets rescue nil
      return nil unless assets

      paths = Array(assets.respond_to?(:paths) ? assets.paths : nil)
      return nil if paths.empty?

      logical = path.sub(%r{\A/assets/}, "").sub(%r{\A/}, "")
      paths.each do |asset_root|
        candidate = File.expand_path(logical, asset_root.to_s)
        return candidate if File.file?(candidate)
      end
      nil
    rescue StandardError
      nil
    end

    # --- Filesystem walk -----------------------------------------------------

    # Many Rails apps emit `<script src="/application-abc123.js">` (jsbundling)
    # or `<link href="/application.css">` (cssbundling). Neither Propshaft nor
    # Sprockets owns those — they live under app/assets/builds and public/.
    def resolve_via_filesystem(path)
      basename = File.basename(path)
      return nil if basename.empty? || basename == "/"

      app_root = root
      return nil unless app_root

      search_roots.each do |root_segment|
        absolute = File.join(app_root, root_segment, basename)
        return absolute if File.file?(absolute)
      end
      nil
    end

    # As a last resort try the URL path verbatim under public/, where Rails
    # serves precompiled assets and any static file mounted with sendfile.
    def resolve_via_public(path)
      app_root = root
      return nil unless app_root

      candidate = File.join(app_root, "public", path.sub(%r{\A/}, ""))
      return candidate if File.file?(candidate)

      nil
    end

    def root
      @root || (rails_app.respond_to?(:root) ? rails_app.root.to_s : nil)
    end

    def search_roots
      @search_roots ||= DEFAULT_ROOTS
    end
  end
end
