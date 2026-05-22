# frozen_string_literal: true

module Browsable
  module Formatters
    # Emits GitHub Actions workflow commands so findings surface as inline
    # annotations on a pull request. See:
    # https://docs.github.com/actions/reference/workflow-commands-for-github-actions
    class Github
      LEVELS = { error: "error", warning: "warning", info: "notice" }.freeze

      def initialize(report)
        @report = report
      end

      def render
        lines = @report.findings.map { |finding| annotation(finding) }

        if (suggestion = @report.suggestion)
          lines << "::notice title=#{escape_property('browsable: suggested allow_browser')}::" \
                   "#{escape_data(suggestion.line)}"
        end

        lines.join("\n")
      end

      private

      def annotation(finding)
        level = LEVELS.fetch(finding.severity, "warning")
        properties = [
          "file=#{finding.file}",
          "line=#{finding.line}",
          "col=#{finding.column}",
          "title=#{escape_property("browsable: #{finding.feature_name}")}"
        ].join(",")

        "::#{level} #{properties}::#{escape_data(finding.message)}"
      end

      # GitHub requires these characters escaped within workflow commands.
      def escape_data(value)
        value.to_s.gsub("%", "%25").gsub("\r", "%0D").gsub("\n", "%0A")
      end

      def escape_property(value)
        escape_data(value).gsub(":", "%3A").gsub(",", "%2C")
      end
    end
  end
end
