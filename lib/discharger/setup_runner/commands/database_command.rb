# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class DatabaseCommand < BaseCommand
        def execute
          log "Setting up database"
          
          # Drop and recreate development database
          log "Dropping & recreating the development database"
          system! "bin/rails db:drop db:create > /dev/null 2>&1"
          
          # Load schema and run migrations
          log "Loading the database schema"
          system! "bin/rails db:schema:load db:migrate"
          
          # Seed the database
          log "Seeding the database"
          env = config.respond_to?(:seed_env) && config.seed_env ? { "SEED_DEV_ENV" => "true" } : {}
          system!(env, "bin/rails db:seed")
          
          # Setup test database
          log "Dropping & recreating the test database"
          system!({ "RAILS_ENV" => "test" }, "bin/rails db:drop db:create db:schema:load > /dev/null 2>&1")
          
          # Clear logs and temp files
          log "Removing old logs and tempfiles"
          system! "bin/rails log:clear tmp:clear > /dev/null 2>&1"
        end
        
        def can_execute?
          File.exist?(File.join(app_root, "bin/rails"))
        end
        
        def description
          "Setup database"
        end
      end
    end
  end
end