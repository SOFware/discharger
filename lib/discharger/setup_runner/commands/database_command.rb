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
          terminate_database_connections
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
          terminate_database_connections("test")
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
        
        private
        
        def terminate_database_connections(rails_env = nil)
          # Use a Rails runner to terminate connections within the Rails context
          env_vars = rails_env ? { "RAILS_ENV" => rails_env } : {}
          
          runner_script = <<~RUBY
            begin
              # Only proceed if using PostgreSQL
              if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.adapter_name =~ /postgresql/i
                ActiveRecord::Base.connection.execute <<-SQL
                  SELECT pg_terminate_backend(pid)
                  FROM pg_stat_activity
                  WHERE datname = current_database() AND pid <> pg_backend_pid();
                SQL
              end
            rescue => e
              # If we can't connect or terminate, that's okay - the database might not exist yet
              puts "Note: Could not terminate existing connections: \#{e.message}"
            end
          RUBY
          
          system!(env_vars, "bin/rails", "runner", runner_script)
        end
      end
    end
  end
end