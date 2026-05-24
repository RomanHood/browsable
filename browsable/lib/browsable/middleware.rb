# frozen_string_literal: true

module Browsable
  # The Rack middleware behind runtime-mode auditing.
  #
  # Inserted by the RSpec / Minitest drivers (or manually in development), it
  # observes each HTML response, identifies the controller#action that
  # produced it, resolves the effective allow_browser policy for that
  # endpoint, parses the response HTML for asset references, and records the
  # whole tuple into the AuditLog. **No analysis happens here.**
  #
  # The middleware refuses to initialize in `Rails.env.production?` — runtime
  # auditing is strictly for development and test.
  class Middleware
    # Paths under these prefixes are owned by Rails or Action Cable and never
    # represent user-rendered HTML. Auditing them produces noise at best and
    # false attributions at worst.
    SKIP_PREFIXES = ["/rails/", "/assets/", "/packs/", "/cable", "/__"].freeze

    def initialize(app, audit_log: nil, asset_resolver: nil)
      raise Browsable::Error, "Browsable::Middleware refuses to run in production" if production?

      @app = app
      @audit_log = audit_log
      @asset_resolver = asset_resolver
    end

    def call(env)
      status, headers, body = @app.call(env)
      return [status, headers, body] unless auditable?(env, status, headers)

      chunks = drain(body)
      record(env, status, headers, chunks)
      [status, headers, replay(chunks)]
    end

    private

    def production?
      return false unless defined?(Rails) && Rails.respond_to?(:env) && Rails.env

      Rails.env.production?
    end

    def auditable?(env, status, headers)
      return false unless env["REQUEST_METHOD"] == "GET"
      return false unless status.to_i == 200
      return false unless html_content_type?(headers)
      return false if skip_path?(env["PATH_INFO"].to_s)

      true
    end

    def html_content_type?(headers)
      type = content_type(headers)
      return false unless type

      type.include?("text/html")
    end

    # Rack 3 lowercases header keys; Rack 2 preserved the original case. Look
    # both up so we work on either generation.
    def content_type(headers)
      headers["Content-Type"] || headers["content-type"]
    end

    def skip_path?(path)
      SKIP_PREFIXES.any? { |prefix| path.start_with?(prefix) }
    end

    def record(env, _status, _headers, chunks)
      controller = env["action_controller.instance"]
      return unless controller
      return unless controller.respond_to?(:action_name) && controller.respond_to?(:class)

      action = controller.action_name.to_s
      return if action.empty?

      html = chunks.join
      return if html.empty?

      extraction = HtmlExtractor.extract(html, asset_resolver: asset_resolver)
      policy = PolicyResolver.for(controller.class, action)

      audit_log.record(
        endpoint: "#{controller.class.name}##{action}",
        request_path: env["PATH_INFO"].to_s,
        policy: policy,
        html: html,
        asset_paths: extraction.asset_paths,
        inline_blocks: extraction.inline_blocks
      )
    rescue StandardError
      # Recording must never break the request cycle. If something failed,
      # silently drop the entry rather than corrupt the response.
      nil
    end

    # Rack body is an Enumerable<String>; calling .each consumes single-shot
    # streamed bodies, so we drain into chunks once and replay below.
    def drain(body)
      chunks = []
      body.each { |chunk| chunks << chunk.to_s }
      chunks
    ensure
      body.close if body.respond_to?(:close)
    end

    # Reconstruct a body that downstream middleware (and the server) can
    # iterate normally. Returning the array directly satisfies Rack's body
    # contract.
    def replay(chunks)
      chunks
    end

    def audit_log
      @audit_log ||= Browsable.audit_log
    end

    def asset_resolver
      @asset_resolver ||= Browsable.asset_resolver
    end
  end
end
