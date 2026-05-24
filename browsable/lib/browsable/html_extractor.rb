# frozen_string_literal: true

require "nokogiri"

module Browsable
  # Pure-Ruby parser for a rendered HTML response. Walks the document for asset
  # references (`<link rel="stylesheet">`, `<script src>`) and inline CSS/JS
  # blocks, then asks the configured AssetResolver to translate each external
  # URL into an on-disk path.
  #
  # This is the only HTML work the runtime middleware performs per request.
  # No analysis happens here — that is the TestReport's job, end of suite.
  class HtmlExtractor
    # url           — the raw href/src as written in the HTML
    # resolved_path — absolute on-disk path, or nil when AssetResolver missed
    # kind          — :css or :js
    AssetRef = Data.define(:url, :resolved_path, :kind)

    # content — the textual body of an inline <style> or <script>
    # kind    — :css or :js
    InlineBlock = Data.define(:content, :kind)

    # The aggregated extraction result returned to the middleware.
    Extraction = Data.define(:asset_paths, :inline_blocks) do
      # Just the resolved on-disk paths — the shape downstream callers want.
      def resolved_paths
        asset_paths.filter_map(&:resolved_path).uniq
      end
    end

    EMPTY = Extraction.new(asset_paths: [], inline_blocks: []).freeze

    attr_reader :html, :asset_resolver

    def initialize(html, asset_resolver: nil)
      @html = html.to_s
      @asset_resolver = asset_resolver
    end

    # Convenience entry point used by the middleware so a single call replaces
    # both `new(...)` and `.extract` at the call site.
    def self.extract(html, asset_resolver: nil)
      new(html, asset_resolver: asset_resolver).run
    end

    def run
      return EMPTY if html.strip.empty?

      doc = Nokogiri::HTML5.parse(html)
      Extraction.new(
        asset_paths: extract_assets(doc),
        inline_blocks: extract_inline_blocks(doc)
      )
    rescue StandardError
      EMPTY
    end

    private

    def extract_assets(doc)
      refs = []

      doc.css('link[rel~="stylesheet"][href]').each do |link|
        href = link["href"].to_s.strip
        next if href.empty?

        refs << AssetRef.new(url: href, resolved_path: resolve(href), kind: :css)
      end

      doc.css("script[src]").each do |script|
        src = script["src"].to_s.strip
        next if src.empty?

        refs << AssetRef.new(url: src, resolved_path: resolve(src), kind: :js)
      end

      refs.uniq(&:url)
    end

    def extract_inline_blocks(doc)
      blocks = []

      doc.css("style").each do |node|
        content = node.content.to_s
        blocks << InlineBlock.new(content: content, kind: :css) unless content.strip.empty?
      end

      doc.css("script:not([src])").each do |node|
        # Skip non-executable script blocks: importmaps, JSON payloads, etc. —
        # they aren't JavaScript and eslint would choke on them.
        next if inert_script?(node)

        content = node.content.to_s
        blocks << InlineBlock.new(content: content, kind: :js) unless content.strip.empty?
      end

      blocks
    end

    def inert_script?(node)
      type = node["type"].to_s.downcase
      return false if type.empty? || type == "text/javascript" || type == "module"
      return false if type == "application/javascript"

      true
    end

    def resolve(url)
      return nil unless asset_resolver

      asset_resolver.resolve(url)
    end
  end
end
