# frozen_string_literal: true

require "fileutils"

module Discharger
  module SetupRunner
    # Creates the counterpart of each example file that is missing, so Rails
    # can boot on a fresh clone. Returns the created paths relative to app_root.
    module ExampleFiles
      CONFIG = "config/**/*.example"
      ENV_FILE = ".env.example"

      def self.create_missing(app_root, patterns = [CONFIG, ENV_FILE])
        patterns.flat_map { |pattern| Dir.glob(pattern, base: app_root) }.sort.filter_map do |example|
          target = example.delete_suffix(".example")
          next if File.exist?(File.join(app_root, target))

          FileUtils.cp(File.join(app_root, example), File.join(app_root, target))
          target
        end
      end
    end
  end
end
