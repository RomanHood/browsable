# frozen_string_literal: true

module Browsable
  module Drivers
    # The RSpec driver — activated by `require "browsable/rspec"`.
    #
    # On load it (a) verifies a Rails app is reachable, (b) inserts the
    # runtime middleware idempotently, and (c) registers before(:suite) /
    # after(:suite) hooks so the audit log is cleared and the report rendered
    # automatically without per-spec boilerplate.
    class RSpec
      DEFAULTS = {
        fail_on: :error,        # :error | :warning | :never
        format: :human,         # :human | :json | :github
        output: :stdout,        # :stdout | :stderr | "path/to/file"
        enabled: true
      }.freeze

      class Configuration
        attr_accessor :fail_on, :format, :output, :enabled

        def initialize
          DEFAULTS.each { |key, value| public_send("#{key}=", value) }
        end
      end

      class << self
        def configuration
          @configuration ||= Configuration.new
        end

        def configure
          yield configuration
        end

        def reset!
          @configuration = nil
        end

        # Wire the middleware and RSpec hooks. Called once when the entry-point
        # file is required.
        def install!
          require "rspec/core"
          ensure_rails!
          insert_middleware
          register_hooks
        end

        # The Rails app whose middleware stack we mutate. Extracted so tests
        # can stub the lookup.
        def rails_application
          return nil unless defined?(::Rails)

          ::Rails.application
        end

        private

        def ensure_rails!
          return if defined?(::Rails) && rails_application

          raise Browsable::Error,
                "browsable/rspec requires a Rails application — load it after Rails is initialized."
        end

        def insert_middleware
          app = rails_application
          return unless app

          stack = app.config.middleware
          return if middleware_present?(stack)

          stack.use(Browsable::Middleware)
        end

        def middleware_present?(stack)
          stack.respond_to?(:include?) && stack.include?(Browsable::Middleware)
        rescue StandardError
          false
        end

        def register_hooks
          ::RSpec.configure do |c|
            c.before(:suite) { Browsable::Drivers::RSpec.before_suite }
            c.after(:suite)  { Browsable::Drivers::RSpec.after_suite }
          end
        end

        public

        def before_suite
          Browsable.audit_log.clear
        end

        def after_suite
          return unless configuration.enabled
          return if Browsable.audit_log.empty?

          report = Browsable::TestReport.new
          emit(report)
          report.fail_suite_if_errors!(fail_on: configuration.fail_on) unless configuration.fail_on == :never
        end

        def emit(report)
          rendered = report.render(format: configuration.format)
          target = configuration.output
          case target
          when :stdout then $stdout.puts(rendered)
          when :stderr then $stderr.puts(rendered)
          when IO, StringIO then target.puts(rendered)
          else File.write(target.to_s, rendered)
          end
        end
      end
    end
  end
end
