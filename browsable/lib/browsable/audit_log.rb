# frozen_string_literal: true

require "concurrent"
require "set"

module Browsable
  # Thread-safe, in-memory accumulator for responses observed by the runtime
  # middleware. Recording is per-request; analysis is one-shot at suite end.
  #
  # A single global instance lives at `Browsable.audit_log`. Tests can replace
  # it (or call `#clear`) for isolation. Nothing in this class invokes an
  # analyzer — recording must be cheap and side-effect-free.
  class AuditLog
    # One observed response.
    #
    #   endpoint     "PostsController#show"
    #   request_path "/posts/42"
    #   policy       Browsable::Policy (the effective policy for this endpoint)
    #   html         the rendered response body as a String
    #   asset_paths  Array<HtmlExtractor::AssetRef>
    #   inline_blocks Array<HtmlExtractor::InlineBlock>
    #   recorded_at  Time (used for debugging only, not analysis)
    Entry = Data.define(
      :endpoint, :request_path, :policy, :html,
      :asset_paths, :inline_blocks, :recorded_at
    )

    def initialize
      @entries = Concurrent::Array.new
    end

    def record(endpoint:, request_path:, policy:, html:, asset_paths:, inline_blocks:)
      @entries << Entry.new(
        endpoint: endpoint,
        request_path: request_path,
        policy: policy,
        html: html,
        asset_paths: asset_paths,
        inline_blocks: inline_blocks,
        recorded_at: Time.now
      )
    end

    def entries
      @entries.to_a
    end

    def empty?
      @entries.empty?
    end

    def size
      @entries.size
    end

    # The deduplicated union of every resolved asset path seen across all
    # entries — what TestReport hands to stylelint and eslint in one go.
    def asset_path_universe
      paths = Set.new
      @entries.each do |entry|
        entry.asset_paths.each do |ref|
          paths << ref.resolved_path if ref.resolved_path
        end
      end
      paths
    end

    # Every entry whose response loaded the given asset path. Used to attribute
    # an end-of-suite finding back to the endpoints that triggered it.
    def entries_loading(asset_path)
      @entries.select do |entry|
        entry.asset_paths.any? { |ref| ref.resolved_path == asset_path }
      end
    end

    def clear
      @entries.clear
    end
  end

  class << self
    def audit_log
      @audit_log ||= AuditLog.new
    end

    # Tests / drivers can install their own instance.
    attr_writer :audit_log

    # The shared AssetResolver. Lazily constructed against the current Rails
    # app the first time it's asked for.
    def asset_resolver
      @asset_resolver ||= AssetResolver.new
    end

    attr_writer :asset_resolver
  end
end
