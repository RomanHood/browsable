# frozen_string_literal: true

require "rails/railtie"

module Browsable
  # Wires browsable into a host Rails application: registers the rake tasks and
  # lets Rails discover the install generator under lib/generators.
  #
  # Loaded only when Rails is present (see the conditional require in
  # lib/browsable.rb).
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("rake_tasks.rb", __dir__)
    end
  end
end
