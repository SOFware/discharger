# frozen_string_literal: true

require_relative "base_command"
require "fileutils"

module Discharger
  module SetupRunner
    module Commands
      class ConfigCommand < BaseCommand
        def execute
          log "Ensuring configuration files are present"

          # Copy database.yml if needed
          database_yml = File.join(app_root, "config/database.yml")
          database_yml_example = File.join(app_root, "config/database.yml.example")

          if !File.exist?(database_yml) && File.exist?(database_yml_example)
            FileUtils.cp(database_yml_example, database_yml)
            log "Copied config/database.yml.example to config/database.yml"
          end

          # Copy Procfile.dev to Procfile if needed
          procfile = File.join(app_root, "Procfile")
          procfile_dev = File.join(app_root, "Procfile.dev")

          if !File.exist?(procfile) && File.exist?(procfile_dev)
            FileUtils.cp(procfile_dev, procfile)
            log "Copied Procfile.dev to Procfile"
          end

          # Copy any other example config files
          Dir.glob(File.join(app_root, "config/**/*.example")).each do |example_file|
            config_file = example_file.sub(/\.example$/, "")
            unless File.exist?(config_file)
              FileUtils.cp(example_file, config_file)
              log "Copied #{example_file.sub(app_root + "/", "")} to #{config_file.sub(app_root + "/", "")}"
            end
          end
        end

        def can_execute?
          true
        end

        def description
          "Setup configuration files"
        end
      end
    end
  end
end
