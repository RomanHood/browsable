# frozen_string_literal: true

module Browsable
  # Scans every controller and controller-concern for `allow_browser` callsites,
  # so the report can show the full policy landscape — not just the one on
  # ApplicationController that drives the audit target.
  #
  # This is deliberately *discovery only*. browsable does not try to map each
  # frontend asset to the endpoints (and therefore policies) that serve it:
  # CSS and importmap JavaScript are global assets, pulled in by layout helpers
  # on essentially every page, so they have no single owning controller action.
  # The scanner surfaces the policies; the user decides what to audit against.
  class PolicyScanner
    # One discovered allow_browser callsite.
    #   scope   — the controller/concern it lives in (e.g. "Api::PostsController")
    #   file    — path relative to the project root
    #   result  — a PolicyDetector::Result (the resolved versions, or a note)
    #   only    — action-name strings the policy is limited to, or nil
    #   except  — action-name strings the policy excludes, or nil
    #   concern — true when the callsite is in app/controllers/concerns
    Policy = Data.define(:scope, :file, :result, :only, :except, :concern) do
      def application_controller? = scope == "ApplicationController"
      def scoped? = !only.nil? || !except.nil?
    end

    CONTROLLER_GLOB = "app/controllers/**/*.rb"

    def self.call(root) = new(root).call

    def initialize(root)
      @root = File.expand_path(root)
      @detector = PolicyDetector.new(@root)
    end

    # => Array<Policy>, in a stable (path-sorted) order.
    def call
      Dir.glob(File.join(@root, CONTROLLER_GLOB)).sort.flat_map { |file| scan_file(file) }
    rescue StandardError
      []
    end

    private

    def scan_file(file)
      @detector.scan_calls(File.read(file)).map do |call|
        Policy.new(
          scope: scope_for(file),
          file: file.sub("#{@root}/", ""),
          result: call.result,
          only: call.only,
          except: call.except,
          concern: file.include?("/concerns/")
        )
      end
    rescue StandardError
      []
    end

    # Derive the controller/concern constant name from the file path — robust
    # and free of AST class-name edge cases. app/controllers/api/posts_controller.rb
    # => "Api::PostsController"; concerns/ is dropped from the name.
    def scope_for(file)
      relative = file.sub(%r{\A.*?app/controllers/}, "")
                     .sub(/\.rb\z/, "")
                     .sub(%r{\Aconcerns/}, "")
      relative.split("/").map { |segment| camelize(segment) }.join("::")
    end

    def camelize(segment)
      segment.split("_").map(&:capitalize).join
    end
  end
end
