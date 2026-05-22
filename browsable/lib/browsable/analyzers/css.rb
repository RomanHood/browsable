# frozen_string_literal: true

require "json"
require "tmpdir"

module Browsable
  module Analyzers
    # Audits CSS by shelling out to stylelint with the
    # `stylelint-no-unsupported-browser-features` plugin configured for the
    # project's target. browsable supplies the config; stylelint (and its
    # bundled caniuse data) does the actual compatibility reasoning.
    class CSS < Base
      def required_tools = ["stylelint"]

      def analyze(files)
        return [] if files.empty?

        argv = ["stylelint", "--config", write_stylelintrc,
                "--formatter", "json", *files]
        parse(shell_out(argv, dry_run_key: "BROWSABLE_DRY_RUN_CSS"))
      end

      private

      # Write a throwaway .stylelintrc.json scoped to the current target.
      #
      # TODO(v0.2): pass --resolve-plugins-relative-to so a globally-installed
      # stylelint-no-unsupported-browser-features resolves reliably regardless
      # of where the temp config lives.
      def write_stylelintrc
        dir = Dir.mktmpdir("browsable-stylelint")
        path = File.join(dir, ".stylelintrc.json")
        File.write(path, JSON.pretty_generate(stylelint_config))
        path
      end

      def stylelint_config
        {
          "plugins" => ["stylelint-no-unsupported-browser-features"],
          "rules" => {
            "plugin/no-unsupported-browser-features" => [
              true,
              { "browsers" => target.to_browserslist, "severity" => "warning" }
            ]
          }
        }
      end

      def parse(raw)
        data = JSON.parse(raw)
        return [] unless data.is_a?(Array)

        data.flat_map do |result|
          Array(result["warnings"]).filter_map do |warning|
            finding_from_warning(result["source"], warning)
          end
        end
      rescue JSON::ParserError
        []
      end

      def finding_from_warning(file, warning)
        text = warning["text"].to_s
        # stylelint phrases the feature as a quoted token, e.g. "css-has".
        feature = text[/"([^"]+)"/, 1] || warning["rule"].to_s
        return nil if ignored_feature?(feature)

        Finding.new(
          feature_id: "css.#{feature}",
          feature_name: feature,
          file: file,
          line: warning["line"] || 1,
          column: warning["column"] || 1,
          required_browser_versions: {}, # stylelint does not expose exact versions
          target_browser_versions: target.browsers,
          severity: warning["severity"] == "error" ? severity_for("below_target") : :warning,
          message: text
        )
      end
    end
  end
end
