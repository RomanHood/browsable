# frozen_string_literal: true

module Browsable
  module Sources
    # Base class for a file source. A source expands a set of globs (relative
    # to the project root) into a concrete, de-duplicated list of file paths.
    #
    # Sources only *discover* files — routing each file to the right analyzer
    # is the orchestrator's job, done by extension.
    class Base
      attr_reader :root, :globs, :excludes

      def initialize(root:, globs:, excludes: [])
        @root = File.expand_path(root)
        @globs = Array(globs)
        @excludes = Array(excludes)
      end

      # A short symbol naming this source, used in reports (e.g. :stylesheets).
      def name
        self.class.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase.to_sym
      end

      # The discovered files: existing, non-excluded, sorted, unique.
      def files
        globs
          .flat_map { |glob| Dir.glob(File.join(root, glob), File::FNM_EXTGLOB) }
          .select { |path| File.file?(path) }
          .reject { |path| excluded?(path) }
          .uniq
          .sort
      end

      def any? = files.any?

      private

      def excluded?(path)
        excludes.any? do |glob|
          File.fnmatch?(File.join(root, glob), path, File::FNM_EXTGLOB | File::FNM_PATHNAME)
        end
      end
    end
  end
end
