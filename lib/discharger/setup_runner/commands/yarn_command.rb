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

              package_json_path = File.join(app_root, "package.json")
              if File.exist?(package_json_path)
                begin
                  require "json"
                  package_json = JSON.parse(File.read(package_json_path))

                  if package_json["packageManager"]&.start_with?("yarn@")
                    yarn_spec = package_json["packageManager"].split("+").first
                    log "Using #{yarn_spec} from package.json"
                    system! "corepack use #{yarn_spec}"
                  else
                    system! "corepack use yarn@stable"
                  end
                rescue JSON::ParserError => e
                  log "Warning: Could not parse package.json: #{e.message}"
                  system! "corepack use yarn@stable"
                end
              else
                system! "corepack use yarn@stable"
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
      end
    end
  end
end
