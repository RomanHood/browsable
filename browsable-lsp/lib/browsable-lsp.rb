# frozen_string_literal: true

# browsable-lsp — a Language Server Protocol server built on the browsable gem.
#
# The core gem already sets up Zeitwerk for the Browsable namespace; this small
# companion gem uses an explicit require manifest instead. With only a handful
# of files, a flat manifest is clearer than a second autoloader co-managing the
# shared Browsable:: namespace.

require "browsable"
require "language_server-protocol"

require_relative "browsable/lsp/version"
require_relative "browsable/lsp/diagnostics"
require_relative "browsable/lsp/handlers/initialize"
require_relative "browsable/lsp/handlers/did_open"
require_relative "browsable/lsp/handlers/did_change"
require_relative "browsable/lsp/server"
