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

              if (yarn_spec = package_manager_yarn_spec)
                log "Using #{yarn_spec} from package.json"
                system! "corepack install"
              else
                system! "corepack install -g yarn@stable"
              end
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

        private

        def package_manager_yarn_spec
          require "json"
          package_manager = JSON.parse(File.read(File.join(app_root, "package.json")))["packageManager"]
          package_manager.split("+").first if package_manager&.start_with?("yarn@")
        rescue JSON::ParserError => e
          log "Warning: Could not parse package.json: #{e.message}"
          nil
        end
      end
    end
  end
end
