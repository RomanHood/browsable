# frozen_string_literal: true

module Browsable
  module Drivers
    # The Minitest driver — activated by `require "browsable/minitest"`.
    #
    # Mirrors the RSpec driver: insert the middleware, clear the audit log on
    # boot, render the TestReport once Minitest finishes. Uses
    # `Minitest.after_run` for end-of-suite reporting.
    class Minitest
      DEFAULTS = {
        fail_on: :error,
        format: :human,
        output: :stdout,
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

        def install!
          require "minitest"
          ensure_rails!
          insert_middleware
          Browsable.audit_log.clear
          ::Minitest.after_run { Browsable::Drivers::Minitest.after_run }
        end

        def rails_application
          return nil unless defined?(::Rails)

          ::Rails.application
        end

        def after_run
          return unless configuration.enabled
          return if Browsable.audit_log.empty?

          report = Browsable::TestReport.new
          emit(report)
          report.fail_suite_if_errors!(fail_on: configuration.fail_on) unless configuration.fail_on == :never
        end

        private

        def ensure_rails!
          return if defined?(::Rails) && rails_application

          raise Browsable::Error,
                "browsable/minitest requires a Rails application — load it after Rails is initialized."
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
