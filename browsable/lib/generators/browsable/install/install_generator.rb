# frozen_string_literal: true

require "rails/generators/base"
require "browsable"

module Browsable
  module Generators
    # `rails g browsable:install` — writes a fully-commented config/browsable.yml.
    #
    # The generated file is a self-documenting reference: every option is
    # present, commented out, and set to its default. browsable needs no config
    # to run; this file exists only so overriding a default is one uncomment away.
    class InstallGenerator < Rails::Generators::Base
      desc "Creates a commented config/browsable.yml you can edit to override defaults."
      source_root File.expand_path("templates", __dir__)

      class_option :minimal, type: :boolean, default: false,
                             desc: "Write section headers only, not the full commented body"
      class_option :target, type: :string,
                            desc: "Pre-populate target.source: manual with this query"
      class_option :force, type: :boolean, default: false,
                           desc: "Overwrite an existing config/browsable.yml"

      def create_config_file
        if File.exist?(config_destination) && !options[:force]
          say_status :skip, "config/browsable.yml already exists (pass --force to overwrite)", :yellow
          @skipped = true
          return
        end

        template "browsable.yml.tt", "config/browsable.yml", force: options[:force]
      end

      def print_summary
        return if @skipped

        say ""
        say "browsable: created config/browsable.yml", :green
        say "  Every option is commented out and set to its default — the file is", :white
        say "  optional and exists only for overrides. Uncomment a line to change it.", :white
        say "  Run `bundle exec browsable audit` for your first audit.", :white
      end

      private

      def config_destination
        File.join(destination_root, "config/browsable.yml")
      end

      # The following three methods are referenced as bare names by the ERB
      # template (templates/browsable.yml.tt). They are private so Rails does
      # not run them as generator steps.

      def detected_comment
        case allow_browser_policy
        when nil
          "# (No allow_browser call detected in ApplicationController.)"
        when Hash
          "# Detected: ApplicationController declares an explicit allow_browser versions hash."
        else
          "# Detected: ApplicationController uses `allow_browser versions: :#{allow_browser_policy}`"
        end
      end

      def manual_query
        options[:target]
      end

      def minimal
        options[:minimal]
      end

      # Reuse the core gem's detector so the generator and the CLI agree on
      # exactly which allow_browser forms (symbol, hash, commented-out) count.
      def allow_browser_policy
        return @allow_browser_policy if defined?(@allow_browser_policy)

        @allow_browser_policy = Browsable::Config.load(root: destination_root).detected_policy
      end
    end
  end
end
