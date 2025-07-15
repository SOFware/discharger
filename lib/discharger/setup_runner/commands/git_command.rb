# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class GitCommand < BaseCommand
        def execute
          log "Setting up git configuration"
          
          # Set up commit template if it exists
          commit_template = File.join(app_root, ".commit-template")
          if File.exist?(commit_template)
            system! "git config --local commit.template .commit-template"
            log "Git commit template configured"
          end
          
          # Set up git hooks if .githooks directory exists
          githooks_dir = File.join(app_root, ".githooks")
          if File.directory?(githooks_dir)
            system! "git config --local core.hooksPath .githooks"
            log "Git hooks path configured"
          end
          
          # Any other git config from the setup.yml
          if config.respond_to?(:git_config) && config.git_config
            config.git_config.each do |key, value|
              system! "git config --local #{key} '#{value}'"
              log "Set git config #{key}"
            end
          end
        end
        
        def can_execute?
          File.directory?(File.join(app_root, ".git"))
        end
        
        def description
          "Setup git configuration"
        end
      end
    end
  end
end