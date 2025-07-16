# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class YarnCommand < BaseCommand
        def execute
          log "Installing Node modules"

          # Enable corepack if yarn.lock exists (Yarn 2+)
          if File.exist?(File.join(app_root, "yarn.lock"))
            if system_quiet("which corepack")
              system! "corepack enable"
              system! "corepack use yarn@stable"
            end

            # Install dependencies
            system_quiet("yarn check --check-files > /dev/null 2>&1") || system!("yarn install")
          elsif File.exist?(File.join(app_root, "package-lock.json"))
            # NPM project
            log "Found package-lock.json, using npm"
            system! "npm ci"
          elsif File.exist?(File.join(app_root, "package.json"))
            # Generic package.json - try yarn first, fall back to npm
            if system_quiet("which yarn")
              system! "yarn install"
            else
              system! "npm install"
            end
          end
        end

        def can_execute?
          File.exist?(File.join(app_root, "package.json"))
        end

        def description
          "Install JavaScript dependencies"
        end
      end
    end
  end
end
