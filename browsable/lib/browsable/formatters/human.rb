# frozen_string_literal: true

require "pastel"

module Browsable
  module Formatters
    # Pretty terminal output: findings grouped by file, then sorted by position.
    # File paths are emitted as OSC 8 hyperlinks so modern terminals make them
    # clickable; colour is disabled automatically when stdout is not a TTY.
    class Human
      ICONS = { error: "✗", warning: "▲", info: "•" }.freeze

      def initialize(report, color: $stdout.tty?)
        @report = report
        @pastel = Pastel.new(enabled: color)
      end

      def render
        sections = [header, notes, body, skips, summary,
                    controller_policies, policy_suggestion].reject(&:empty?)
        sections.join("\n")
      end

      private

      attr_reader :report, :pastel

      def header
        target = report.target
        lines = [pastel.bold("browsable audit")]
        if target
          browsers = target.browsers.map { |name, version| "#{name} #{version}" }.join(", ")
          lines << pastel.dim("target: #{target.query}  (#{browsers})")
        end
        lines << pastel.dim("config: #{report.config_file || 'none (no config file)'}")
        lines.join("\n") + "\n"
      end

      # Run-level caveats — most importantly, a target that could not be
      # inferred. Shown right under the header so the target line above makes
      # sense.
      def notes
        return "" if report.notes.empty?

        report.notes.map { |note| pastel.yellow("! #{note}") }.join("\n") + "\n"
      end

      def body
        return pastel.green("✓ No browser-compatibility issues found.\n") if report.empty?

        report.findings_by_file.map { |file, findings| file_section(file, findings) }.join("\n")
      end

      def file_section(file, findings)
        lines = [pastel.underline(hyperlink(file))]
        findings.each { |finding| lines << finding_line(finding) }
        lines.join("\n") + "\n"
      end

      def finding_line(finding)
        icon = colorize(finding.severity, ICONS.fetch(finding.severity, "•"))
        location = pastel.dim("#{finding.line}:#{finding.column}")
        feature = pastel.cyan(finding.feature_name)
        "  #{icon} #{location}  #{feature}  #{finding.message}"
      end

      def skips
        return "" if report.skips.empty?

        lines = [pastel.yellow.bold("Skipped:")]
        report.skips.each do |skip|
          lines << pastel.yellow("  ! #{skip.kind}: #{skip.reason}")
        end
        lines.join("\n") + "\n"
      end

      def summary
        e = report.errors.size
        w = report.warnings.size
        i = report.infos.size
        parts = [
          colorize(:error, "#{e} error#{'s' unless e == 1}"),
          colorize(:warning, "#{w} warning#{'s' unless w == 1}"),
          colorize(:info, "#{i} info#{'s' unless i == 1}")
        ]
        pastel.bold("#{parts.join('  ')}  across #{report.findings_by_file.size} file(s)") + "\n"
      end

      # A copy-pasteable allow_browser line that raises the offending browsers
      # to the versions the flagged code requires.
      def policy_suggestion
        suggestion = report.suggestion
        return "" unless suggestion

        lines = [pastel.bold("Suggested allow_browser policy")]
        lines << pastel.dim("  Raises the minimums so every permitted browser can run the flagged code:")
        lines << ""
        lines << "    #{pastel.cyan(suggestion.line)}"
        lines << ""
        suggestion.bumps.each do |browser, change|
          lines << pastel.dim("    #{browser}: #{change[:from]} → #{change[:to]}")
        end
        lines << pastel.dim("  Or address it in the code instead — browsable reports, you decide.")
        lines.join("\n") + "\n"
      end

      # The policy landscape: every allow_browser callsite found across the
      # app's controllers. Shown only when there is more than one policy, or a
      # policy somewhere other than ApplicationController — otherwise the
      # `target:` line in the header already says everything.
      def controller_policies
        policies = report.policies
        return "" if policies.empty?
        return "" if policies.size == 1 && policies.first.application_controller?

        lines = [pastel.bold("Browser policies (#{policies.size} allow_browser callsite(s) found)")]
        policies.each { |policy| lines << "  #{describe_policy(policy)}" }
        lines << ""
        lines << pastel.dim("  The audit above ran against one target. CSS and importmap JS are served")
        lines << pastel.dim("  globally, so a controller with a broader policy means those assets must")
        lines << pastel.dim("  satisfy it too — re-audit with --target, or set `target:` in config, to check.")
        lines.join("\n") + "\n"
      end

      def describe_policy(policy)
        scope = policy.concern ? "#{policy.scope} (concern)" : policy.scope
        scope = scope.ljust(34)
        actions =
          if policy.only then "  (only: #{policy.only.join(', ')})"
          elsif policy.except then "  (except: #{policy.except.join(', ')})"
          else ""
          end
        "#{scope}#{pastel.cyan(policy_versions_label(policy.result))}#{pastel.dim(actions)}"
      end

      def policy_versions_label(result)
        if result.policy.is_a?(Hash)
          "{ #{result.policy.map { |browser, version| "#{browser}: #{version}" }.join(', ')} }"
        elsif result.policy
          ":#{result.policy}"
        else
          result.note ? "(could not resolve)" : "(no versions:)"
        end
      end

      def colorize(severity, text)
        case severity
        when :error   then pastel.red(text)
        when :warning then pastel.yellow(text)
        else pastel.blue(text)
        end
      end

      # OSC 8 hyperlink — clickable in modern terminals, plain text elsewhere.
      def hyperlink(path)
        return path unless $stdout.tty?

        "\e]8;;file://#{path}\e\\#{path}\e]8;;\e\\"
      end
    end
  end
end
