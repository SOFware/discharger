# frozen_string_literal: true

require "fileutils"
require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class EnvCommand < BaseCommand
        def execute
          log "Setting up .env file"

          return log(".env file already exists. Doing nothing.") if File.exist?(".env")
          return log("WARNING: .env.example not found. Skipping .env creation") unless File.exist?(".env.example")

          FileUtils.cp(".env.example", ".env")
          log ".env file created from .env.example"
        end

        def can_execute?
          File.exist?(".env.example")
        end

        def description
          "Setup environment file"
        end
      end
    end
  end
end
