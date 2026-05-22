# frozen_string_literal: true

module Browsable
  module LSP
    module Handlers
      # Handles textDocument/didChange — re-audits a document as it is edited.
      class DidChange
        def initialize(server)
          @server = server
        end

        def call(params)
          uri = params.dig("textDocument", "uri")
          return unless uri

          # Full-sync mode: the final content change carries the whole document.
          text = Array(params["contentChanges"]).last&.fetch("text", nil)
          return if text.nil?

          @server.store(uri, text)
          @server.publish_diagnostics(uri, text)
        end
      end
    end
  end
end
