# frozen_string_literal: true

require "json"

module Browsable
  module Formatters
    # Machine-readable formatter. This is the universal interface: the LSP
    # server and any future MCP server consume exactly this structure. The
    # human and github formatters are just alternate presentations of it.
    class Json
      def initialize(report)
        @report = report
      end

      def render
        JSON.pretty_generate(@report.as_json)
      end
    end
  end
end
