# frozen_string_literal: true

module Browsable
  module LSP
    # The JSON-RPC server loop.
    #
    # Reads LSP messages from stdin, dispatches them to handlers, and writes
    # responses and diagnostics back to stdout — the standard stdio LSP
    # convention. All compatibility analysis is delegated to the browsable gem;
    # this class only speaks the protocol.
    class Server
      def initialize(input: $stdin, output: $stdout)
        # Io::Reader/Writer take an explicit IO (the Stdio:: subclasses hard-code
        # STDIN/STDOUT); passing $stdin/$stdout keeps the default behaviour while
        # letting tests drive the server over StringIO pipes.
        @reader = ::LanguageServer::Protocol::Transport::Io::Reader.new(input)
        @writer = ::LanguageServer::Protocol::Transport::Io::Writer.new(output)
        @documents = {}
        @workspace_root = Dir.pwd
        @shutdown_requested = false
      end

      # Block reading messages until the client disconnects or sends `exit`.
      def start
        @reader.read { |message| dispatch(normalize(message)) }
      end

      # Cache the latest known contents of a document.
      def store(uri, content)
        @documents[uri] = content
      end

      # Audit `content` and push its diagnostics to the client.
      def publish_diagnostics(uri, content)
        diagnostics = Diagnostics.for(uri: uri, content: content, root: @workspace_root)
        notify("textDocument/publishDiagnostics", { uri: uri, diagnostics: diagnostics })
      end

      private

      def dispatch(message)
        method = message["method"]
        id = message["id"]
        params = message["params"] || {}

        case method
        when "initialize"
          @workspace_root = Handlers::Initialize.workspace_root(params) || @workspace_root
          respond(id, Handlers::Initialize.new.call(params))
        when "initialized"
          nil # nothing to do — diagnostics are pushed on open/change
        when "textDocument/didOpen"
          Handlers::DidOpen.new(self).call(params)
        when "textDocument/didChange"
          Handlers::DidChange.new(self).call(params)
        when "textDocument/didClose"
          @documents.delete(params.dig("textDocument", "uri"))
        when "shutdown"
          @shutdown_requested = true
          respond(id, nil)
        when "exit"
          exit(@shutdown_requested ? 0 : 1)
        # TODO(v0.2): textDocument/codeAction — offer "Add @supports fallback"
        # and "Tighten allow_browser to require Safari 15.4+" as quick fixes.
        end
      rescue StandardError => e
        log("error handling #{method}: #{e.class}: #{e.message}")
      end

      def respond(id, result)
        write(jsonrpc: "2.0", id: id, result: result)
      end

      def notify(method, params)
        write(jsonrpc: "2.0", method: method, params: params)
      end

      def write(message)
        @writer.write(message)
      end

      # Diagnostics go to stderr — stdout is reserved for the JSON-RPC channel.
      def log(text)
        warn("[browsable-lsp] #{text}")
      end

      # Normalize every hash key to a String so handlers need not care whether
      # the transport produced symbol or string keys.
      def normalize(object)
        case object
        when Hash  then object.each_with_object({}) { |(k, v), h| h[k.to_s] = normalize(v) }
        when Array then object.map { |element| normalize(element) }
        else object
        end
      end
    end
  end
end
