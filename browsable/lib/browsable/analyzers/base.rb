# frozen_string_literal: true

require "json"
require "open3"

module Browsable
  module Analyzers
    # Base class for analyzers. An analyzer turns a list of files into Findings.
    #
    # browsable owns no parsing or compat-data logic of its own: analyzers are
    # thin adapters over Herb (in-process) or stylelint/eslint (shelled out).
    class Base
      attr_reader :target, :config

      def initialize(target:, config:)
        @target = target
        @config = config
      end

      # @param files [Array<String>] absolute paths to analyze
      # @return [Array<Finding>]
      def analyze(_files)
        raise NotImplementedError, "#{self.class} must implement #analyze"
      end

      # External binaries this analyzer needs on PATH. Empty for in-process ones.
      def required_tools = []

      # The bundled MDN browser-compat-data subset, parsed once and shared.
      def self.compat_data
        @compat_data ||= JSON.parse(
          File.read(File.join(Browsable.data_dir, "bcd-snapshot.json"))
        )
      end

      private

      def compat_data = self.class.compat_data

      # Translate a severity category into a concrete Finding severity symbol,
      # honouring the user's `severity:` config block.
      def severity_for(category)
        (config.severity[category.to_s] || "warning").to_sym
      end

      def ignored_feature?(feature_id)
        config.ignore_features.include?(feature_id)
      end

      def dry_run? = ENV.key?("BROWSABLE_DRY_RUN")

      # Run an external tool and return its stdout.
      #
      # In dry-run mode the process is never spawned: BROWSABLE_DRY_RUN_<KEY>
      # supplies the output instead, either as inline JSON or as a path to a
      # JSON file. This is the seam specs use to inject fake stylelint/eslint
      # output without those tools installed.
      def shell_out(argv, dry_run_key:)
        if dry_run?
          injected = ENV[dry_run_key]
          return File.read(injected) if injected && File.file?(injected)
          return injected if injected && !injected.empty?

          return "[]"
        end

        # stylelint and eslint exit non-zero whenever they report problems, so
        # the exit status is deliberately ignored — only stdout matters here.
        stdout, _stderr, _status = Open3.capture3(*argv)
        stdout
      end
    end
  end
end
