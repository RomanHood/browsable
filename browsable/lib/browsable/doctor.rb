# frozen_string_literal: true

require "open3"
require "shellwords"
require "rbconfig"
require "pastel"

module Browsable
  # Verifies that the external tools browsable shells out to are installed, and
  # guides the user through installing whatever is missing.
  #
  # Herb is a gem dependency and runs in-process, so it is never checked here —
  # only node, npm, stylelint, eslint and eslint-plugin-compat.
  class Doctor
    # A tool browsable depends on. `binary` is nil for packages that ship no
    # executable (checked via the global npm tree instead). `enables` lists the
    # analyzer kinds the tool unlocks.
    Tool = Data.define(:key, :label, :binary, :npm_package, :purpose, :enables, :required) do
      def binary? = !binary.nil?
    end

    # The resolved state of a tool on this machine.
    Status = Data.define(:tool, :installed, :detail) do
      def installed? = installed
    end

    TOOLS = [
      Tool.new(key: :node, label: "node", binary: "node", npm_package: nil,
               purpose: "JavaScript runtime that stylelint and eslint run on",
               enables: %i[css js], required: true),
      Tool.new(key: :npm, label: "npm", binary: "npm", npm_package: nil,
               purpose: "installs the CSS/JS tooling (used by `doctor --fix`)",
               enables: [], required: false),
      Tool.new(key: :stylelint, label: "stylelint", binary: "stylelint",
               npm_package: "stylelint stylelint-no-unsupported-browser-features",
               purpose: "audits CSS for unsupported browser features",
               enables: %i[css], required: true),
      Tool.new(key: :eslint, label: "eslint", binary: "eslint",
               npm_package: "eslint eslint-plugin-compat",
               purpose: "audits JavaScript for unsupported browser features",
               enables: %i[js], required: true),
      Tool.new(key: :eslint_plugin_compat, label: "eslint-plugin-compat", binary: nil,
               npm_package: "eslint-plugin-compat",
               purpose: "the eslint plugin that performs the JS compat checks",
               enables: %i[js], required: true),
      Tool.new(key: :postcss_scss, label: "postcss-scss", binary: nil,
               npm_package: "postcss-scss",
               purpose: "lets stylelint parse SCSS sources (Sprockets apps)",
               enables: %i[scss], required: false)
    ].freeze

    # Analyzer kinds that need no external tooling at all.
    ALWAYS_AVAILABLE = %i[erb html].freeze

    # @param root [String, nil] the project root. When provided, optional tools
    #   (e.g. postcss-scss) are only flagged as missing if the project actually
    #   has files that need them.
    def initialize(root: nil)
      @root = root && File.expand_path(root)
    end

    attr_reader :root

    def statuses
      @statuses ||= TOOLS.map do |tool|
        present = installed?(tool)
        Status.new(tool: tool, installed: present, detail: detail_for(tool, present))
      end
    end

    # True when every *required* tool is present.
    def ok?
      statuses.select { |s| s.tool.required }.all?(&:installed?)
    end

    def missing
      statuses.reject(&:installed?).map(&:tool)
    end

    def postcss_scss_installed?
      tool = TOOLS.find { |t| t.key == :postcss_scss }
      installed?(tool)
    end

    # Whether the project at `root` actually has files that need this tool.
    # For unconditional tools (e.g. node, stylelint) this is always true; for
    # optional tools (e.g. postcss-scss) it depends on what's on disk.
    def needs_tool?(tool)
      return true if tool.required
      return true if tool.enables.empty? # tools that enable nothing are housekeeping
      return true unless root            # no project context: assume needed

      tool.enables.all? { |kind| project_has_kind?(kind) }
    end

    # Optional tools that *would* be needed by this project but aren't installed.
    # Used by the audit CLI to surface targeted skips (e.g. postcss-scss missing
    # only when the project has SCSS files).
    def needed_optional_missing
      missing.select do |tool|
        next false if tool.required

        needs_tool?(tool)
      end
    end

    # Which analyzer kinds can actually run on this machine right now.
    def available_kinds
      # In dry-run mode the external tools are never invoked, so treat them all
      # as available — this keeps specs and `BROWSABLE_DRY_RUN` audits working.
      return %i[css erb html js] if ENV.key?("BROWSABLE_DRY_RUN")

      kinds = ALWAYS_AVAILABLE.dup
      %i[css js].each do |kind|
        needed = TOOLS.select { |tool| tool.enables.include?(kind) }
        kinds << kind if needed.all? { |tool| installed?(tool) }
      end
      kinds
    end

    # A formatted, colourised dependency report.
    def render(color: $stdout.tty?)
      pastel = Pastel.new(enabled: color)
      lines = [pastel.bold("browsable doctor — system dependencies"), ""]

      statuses.each do |status|
        mark = render_mark(pastel, status)
        suffix = render_suffix(pastel, status)
        lines << "  #{mark} #{pastel.bold(status.tool.label)} — #{status.tool.purpose}#{suffix}"
        lines << pastel.dim("      #{status.detail}") if status.detail
      end

      lines << ""
      if ok?
        lines << pastel.green.bold("All required tools are installed. You're ready to audit.")
      else
        lines << pastel.red.bold("Missing required tools — install them with:")
        install_commands.each { |cmd| lines << "  #{pastel.cyan(cmd)}" }
        lines << ""
        lines << pastel.dim("Or run `browsable doctor --fix` to install them automatically.")
      end
      lines.join("\n")
    end

    # Attempt to install everything that is missing. Runnable commands only
    # (npm/brew); anything that needs a manual download is reported, not run.
    def fix!(io: $stdout, input: $stdin, assume_yes: false)
      return true if ok?

      runnable, manual = install_commands.partition { |cmd| cmd.start_with?("npm ", "brew ") }

      manual.each { |cmd| io.puts "Manual step required: #{cmd}" }
      return ok? if runnable.empty?

      io.puts "browsable will run:"
      runnable.each { |cmd| io.puts "  #{cmd}" }
      unless assume_yes
        io.print "Proceed? [y/N] "
        answer = input.gets&.strip&.downcase
        return false unless %w[y yes].include?(answer)
      end

      runnable.each do |cmd|
        io.puts "+ #{cmd}"
        system(cmd)
      end
      @statuses = nil
      @installed_cache = nil
      ok?
    end

    private

    # Install commands cover every required tool plus any optional tool the
    # current project actually needs (e.g. postcss-scss when SCSS is present).
    def install_commands
      missing.select { |tool| tool.required || needs_tool?(tool) }
             .map { |tool| install_command(tool) }
             .uniq
    end

    def install_command(tool)
      case tool.key
      when :node, :npm
        mac? ? "brew install node" : "install Node.js — see https://nodejs.org/en/download"
      else
        "npm install -g #{tool.npm_package}"
      end
    end

    def detail_for(tool, present)
      if present
        tool.binary? ? (tool_version(tool) || "installed") : "installed"
      elsif tool.required || needs_tool?(tool)
        "not found — #{install_command(tool)}"
      else
        "not installed (not needed for this project)"
      end
    end

    def project_has_kind?(kind)
      case kind
      when :scss
        Dir.glob(File.join(root, "app/assets/stylesheets/**/*.{scss,sass}"),
                 File::FNM_EXTGLOB).any?
      else
        true
      end
    end

    # Optional tools that are missing-but-needed get the same red ✗ as required
    # tools. Optional tools the project doesn't need are shown as a dim "—".
    def render_mark(pastel, status)
      return pastel.green("✓") if status.installed?
      return pastel.red("✗") if status.tool.required || needs_tool?(status.tool)

      pastel.dim("—")
    end

    def render_suffix(pastel, status)
      return "" if status.tool.required
      return pastel.dim("  (optional)") if status.installed?
      return pastel.yellow("  (optional, but needed for this project)") if needs_tool?(status.tool)

      pastel.dim("  (optional)")
    end

    def installed?(tool)
      @installed_cache ||= {}
      @installed_cache.fetch(tool.key) do
        @installed_cache[tool.key] = tool.binary? ? binary_on_path?(tool.binary) : npm_package_installed?(tool.npm_package)
      end
    end

    def binary_on_path?(binary)
      _out, status = Open3.capture2e("sh", "-c", "command -v #{Shellwords.escape(binary)}")
      status.success?
    rescue StandardError
      false
    end

    # eslint-plugin-compat ships no executable, so check the global npm tree.
    def npm_package_installed?(package)
      _out, status = Open3.capture2e("npm", "ls", "-g", "--depth=0", package.to_s.split.first)
      status.success?
    rescue Errno::ENOENT
      false # npm itself is missing
    rescue StandardError
      false
    end

    def tool_version(tool)
      out, status = Open3.capture2e(tool.binary, "--version")
      status.success? ? out.strip.lines.first&.strip : nil
    rescue StandardError
      nil
    end

    def mac?
      RbConfig::CONFIG["host_os"].to_s.match?(/darwin|mac os/i)
    end
  end
end
