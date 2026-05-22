# frozen_string_literal: true

require "net/http"
require "uri"
require "tmpdir"
require "digest"

module Browsable
  module Sources
    # Resolves importmap pins to their source and makes that source available
    # to the JavaScript analyzer.
    #
    # Rails importmap apps keep no node_modules: vendored JS is referenced by
    # CDN URL in config/importmap.rb. This source reads those pins and downloads
    # each remote file into a tmpdir so eslint can be pointed at real files.
    #
    # config/importmap.rb is *parsed as text*, never evaluated — running an
    # arbitrary project file just to read string literals is not worth the risk.
    class Importmap
      # `pin "name", to: "url", ...` — captures the name and an optional `to:`.
      PIN_PATTERN = /^\s*pin\s+["']([^"']+)["'](?:[^\n]*?\bto:\s*["']([^"']+)["'])?/

      Pin = Data.define(:name, :url) do
        def remote? = url&.start_with?("http://", "https://")
      end

      attr_reader :root

      def initialize(root:)
        @root = File.expand_path(root)
      end

      def importmap_path
        File.join(root, "config/importmap.rb")
      end

      def present?
        File.file?(importmap_path)
      end

      # All pins declared in config/importmap.rb.
      def pins
        return [] unless present?

        File.read(importmap_path).each_line.filter_map do |line|
          next if line.strip.start_with?("#")

          m = line.match(PIN_PATTERN)
          m && Pin.new(name: m[1], url: m[2])
        end
      end

      # Download every remote pin into `dir` and return the local file paths.
      #
      # Remote fetches are skipped entirely when BROWSABLE_OFFLINE=1 — useful in
      # CI, in air-gapped environments, or when a fast offline audit is wanted.
      def fetch(dir: Dir.mktmpdir("browsable-importmap"))
        return [] if ENV["BROWSABLE_OFFLINE"] == "1"

        pins.select(&:remote?).filter_map do |pin|
          download(pin, dir)
        end
      end

      private

      def download(pin, dir)
        body = http_get(pin.url)
        return nil unless body

        filename = "#{pin.name.gsub(%r{[^\w.-]}, '_')}-#{Digest::SHA1.hexdigest(pin.url)[0, 8]}.js"
        path = File.join(dir, filename)
        File.write(path, body)
        path
      rescue StandardError
        # A single unreachable CDN must not abort the whole audit.
        nil
      end

      def http_get(url, redirects: 3)
        return nil if redirects.negative?

        uri = URI.parse(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                                       open_timeout: 5, read_timeout: 10) do |http|
          http.get(uri.request_uri)
        end

        case response
        when Net::HTTPSuccess
          response.body
        when Net::HTTPRedirection
          http_get(response["location"], redirects: redirects - 1)
        end
      end
    end
  end
end
