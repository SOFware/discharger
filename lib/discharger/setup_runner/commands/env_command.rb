# frozen_string_literal: true

require "fileutils"
require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class EnvCommand < BaseCommand
        def execute
          if File.exist?(".env")
            unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
              require 'rainbow'
              puts Rainbow("  → .env file already exists. Skipping.").yellow
            end
            return
          end
          
          unless File.exist?(".env.example")
            unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
              require 'rainbow'
              puts Rainbow("  → WARNING: .env.example not found. Skipping .env creation").yellow
            end
            return
          end

          simple_action("Creating .env from .env.example") do
            FileUtils.cp(".env.example", ".env")
          end
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
