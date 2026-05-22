# frozen_string_literal: true

require "json"
require "tmpdir"

module Browsable
  module Analyzers
    # Audits JavaScript by shelling out to eslint with eslint-plugin-compat
    # configured for the project's target. As with CSS, browsable supplies the
    # config and eslint (with its bundled compat data) does the reasoning.
    class Javascript < Base
      def required_tools = ["eslint"]

      def analyze(files)
        return [] if files.empty?

        # TODO(v0.2): emit an eslint 9 flat config (eslint.config.mjs) and
        # detect which config format the installed eslint expects.
        argv = ["eslint", "--no-eslintrc", "--config", write_eslintrc,
                "--format", "json", *files]
        parse(shell_out(argv, dry_run_key: "BROWSABLE_DRY_RUN_JS"))
      end

      private

      def write_eslintrc
        dir = Dir.mktmpdir("browsable-eslint")
        path = File.join(dir, ".eslintrc.json")
        File.write(path, JSON.pretty_generate(eslint_config))
        path
      end

      def eslint_config
        {
          "root" => true,
          "parserOptions" => { "ecmaVersion" => "latest", "sourceType" => "module" },
          "env" => { "browser" => true, "es2024" => true },
          "plugins" => ["compat"],
          "extends" => ["plugin:compat/recommended"],
          "settings" => { "browsers" => target.to_browserslist }
        }
      end

      def parse(raw)
        data = JSON.parse(raw)
        return [] unless data.is_a?(Array)

        data.flat_map do |result|
          Array(result["messages"]).filter_map do |message|
            finding_from_message(result["filePath"], message)
          end
        end
      rescue JSON::ParserError
        []
      end

      def finding_from_message(file, message)
        rule = message["ruleId"]
        return nil unless rule # syntax errors etc. carry no ruleId

        text = message["message"].to_s
        # eslint-plugin-compat reports every feature under the `compat/compat`
        # rule; the feature itself is the leading token of the message.
        feature = text[/\A(\S+)/, 1] || rule
        return nil if ignored_feature?(feature)

        Finding.new(
          feature_id: "javascript.#{feature}",
          feature_name: feature,
          file: file,
          line: message["line"] || 1,
          column: message["column"] || 1,
          required_browser_versions: {},
          target_browser_versions: target.browsers,
          severity: message["severity"] == 2 ? severity_for("below_target") : :warning,
          message: text
        )
      end
    end
  end
end
