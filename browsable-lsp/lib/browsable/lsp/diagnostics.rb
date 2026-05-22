# frozen_string_literal: true

require "tmpdir"

module Browsable
  module LSP
    # Audits a single document's contents and converts the resulting browsable
    # Findings into LSP diagnostic hashes ready for textDocument/publishDiagnostics.
    class Diagnostics
      # browsable severity -> LSP DiagnosticSeverity
      #   below_target            -> Error (1)
      #   baseline_newly_available -> Warning (2)
      #   baseline_widely_available -> Information (3)
      SEVERITY = { error: 1, warning: 2, info: 3 }.freeze

      def self.for(uri:, content:, root: Dir.pwd)
        new(uri: uri, content: content, root: root).call
      end

      def initialize(uri:, content:, root:)
        @uri = uri
        @content = content.to_s
        @root = root
      end

      def call
        findings.map { |finding| to_diagnostic(finding) }
      rescue StandardError
        # A diagnostics pass must never crash the editor session.
        []
      end

      private

      def findings
        config = Browsable::Config.load(root: @root)
        analyzer_class = analyzer_for(path)
        return [] unless analyzer_class

        analyzer = analyzer_class.new(target: config.target, config: config)

        if analyzer.is_a?(Browsable::Analyzers::ERB)
          # ERB/HTML analysis is in-process — audit the buffer contents directly.
          analyzer.analyze_source(@content, file: path)
        else
          # CSS/JS need a real file for stylelint/eslint.
          # TODO(v0.2): debounce changes and reuse a per-document temp file.
          audit_via_tempfile(analyzer)
        end
      end

      def audit_via_tempfile(analyzer)
        Dir.mktmpdir("browsable-lsp") do |dir|
          tmp = File.join(dir, File.basename(path))
          File.write(tmp, @content)
          analyzer.analyze([tmp])
        end
      end

      def analyzer_for(file)
        case File.extname(file).downcase
        when ".erb"          then Browsable::Analyzers::ERB
        when ".html", ".htm" then Browsable::Analyzers::HTML
        when ".css", ".scss" then Browsable::Analyzers::CSS
        when ".js", ".mjs"   then Browsable::Analyzers::Javascript
        end
      end

      def path
        @path ||= @uri.to_s.sub(%r{\Afile://}, "")
      end

      def to_diagnostic(finding)
        line = [finding.line.to_i - 1, 0].max
        character = [finding.column.to_i - 1, 0].max
        span = finding.feature_name.to_s.length.clamp(1, 200)

        {
          range: {
            start: { line: line, character: character },
            end:   { line: line, character: character + span }
          },
          severity: SEVERITY.fetch(finding.severity, 2),
          source: "browsable",
          code: finding.feature_id,
          message: finding.message
        }
      end
    end
  end
end
