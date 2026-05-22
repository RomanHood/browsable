# frozen_string_literal: true

module Browsable
  module LSP
    module Handlers
      # Handles textDocument/didOpen — audits a freshly-opened document and
      # publishes its diagnostics.
      class DidOpen
        def initialize(server)
          @server = server
        end

        def call(params)
          document = params["textDocument"] || {}
          uri = document["uri"]
          return unless uri

          text = document["text"].to_s
          @server.store(uri, text)
          @server.publish_diagnostics(uri, text)
        end
      end
    end
  end
end
