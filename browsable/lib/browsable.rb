# frozen_string_literal: true

require "zeitwerk"
require_relative "browsable/version"

# browsable — a Rails-aware browser-compatibility audit toolkit.
#
# This file boots the Zeitwerk autoloader and declares the gem's error
# hierarchy. Every other constant under Browsable:: is autoloaded on first use.
module Browsable
  # Base class for every error browsable raises deliberately.
  class Error < StandardError; end

  # Raised when a required external tool (node, stylelint, ...) is missing.
  class DependencyError < Error; end

  # Raised when a config file exists but cannot be parsed or is invalid.
  class ConfigError < Error; end

  class << self
    # The shared Zeitwerk loader. Exposed so specs (and rake) can eager-load.
    attr_accessor :loader

    # Absolute path to the gem's bundled `data/` directory.
    def data_dir
      File.expand_path("../data", __dir__)
    end
  end
end

Browsable.loader = Zeitwerk::Loader.for_gem
Browsable.loader.inflector.inflect(
  "cli"   => "CLI",
  "css"   => "CSS",
  "erb"   => "ERB",
  "html"  => "HTML",
  "rspec" => "RSpec"
)
# These files intentionally do not define a constant matching their path.
Browsable.loader.ignore("#{__dir__}/browsable/version.rb")
Browsable.loader.ignore("#{__dir__}/browsable/rake_tasks.rb")
Browsable.loader.ignore("#{__dir__}/browsable/railtie.rb")
# Driver entry points: they require the gem and call into Drivers::X.install!.
Browsable.loader.ignore("#{__dir__}/browsable/rspec.rb")
Browsable.loader.ignore("#{__dir__}/browsable/minitest.rb")
# Rails generators are discovered and loaded by Rails itself, not Zeitwerk.
Browsable.loader.ignore("#{__dir__}/generators")
Browsable.loader.setup

# The railtie wires rake tasks into a host Rails app. Only relevant inside Rails.
require_relative "browsable/railtie" if defined?(Rails::Railtie)
