# frozen_string_literal: true

require "rails/generators/base"

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
        if allow_browser_policy
          "# Detected: ApplicationController uses `allow_browser versions: :#{allow_browser_policy}`"
        else
          "# (No allow_browser call detected in ApplicationController.)"
        end
      end

      def manual_query
        options[:target]
      end

      def minimal
        options[:minimal]
      end

      def allow_browser_policy
        return @allow_browser_policy if defined?(@allow_browser_policy)

        controller = File.join(destination_root, "app/controllers/application_controller.rb")
        @allow_browser_policy =
          if File.file?(controller) &&
             (match = File.read(controller).match(/allow_browsers?\s+(?:versions:\s*)?:(\w+)/))
            match[1]
          end
      end
    end
  end
end
