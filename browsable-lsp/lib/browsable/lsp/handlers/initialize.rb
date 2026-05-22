# frozen_string_literal: true

module Browsable
  module LSP
    module Handlers
      # Handles the `initialize` request: advertises the server's capabilities.
      class Initialize
        def call(_params)
          {
            capabilities: {
              # 1 = Full document sync — the client resends the whole buffer on
              # every change. Simple and fine for the file sizes browsable sees.
              textDocumentSync: { openClose: true, change: 1 }
            },
            serverInfo: { name: "browsable-lsp", version: Browsable::LSP::VERSION }
          }
        end

        # Best-effort extraction of the workspace root from initialize params.
        # browsable's Config is then loaded relative to it.
        def self.workspace_root(params)
          uri = params["rootUri"] || params.dig("workspaceFolders", 0, "uri")
          return params["rootPath"] if uri.nil?

          uri.to_s.sub(%r{\Afile://}, "")
        end
      end
    end
  end
end
