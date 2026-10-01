# frozen_string_literal: true

require_relative "base_command"
require_relative "../example_files"
require "fileutils"

module Discharger
  module SetupRunner
    module Commands
      class ConfigCommand < BaseCommand
        def execute
          log "Ensuring configuration files are present"

          # Copy Procfile.dev to Procfile if needed
          procfile = File.join(app_root, "Procfile")
          procfile_dev = File.join(app_root, "Procfile.dev")

          if !File.exist?(procfile) && File.exist?(procfile_dev)
            FileUtils.cp(procfile_dev, procfile)
            log "Copied Procfile.dev to Procfile"
          end

          # No-op after Discharger::Setup; covers a Runner used without it.
          ExampleFiles.create_missing(app_root, [ExampleFiles::CONFIG]).each do |path|
            log "Copied #{path}.example to #{path}"
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
