# frozen_string_literal: true

require_relative "base_command"
require "open3"

module Discharger
  module SetupRunner
    module Commands
      class DatabaseCommand < BaseCommand
        def execute
          # Drop and recreate development database
          terminate_database_connections
          with_spinner("Dropping and recreating development database") do
            _stdout, stderr, status = Open3.capture3("bash", "-c", "bin/rails db:drop db:create > /dev/null 2>&1")
            if status.success?
              { success: true }
            else
              { success: false, error: "Failed to drop/create database: #{stderr}" }
            end
          end
          
          # Load schema and run migrations
          with_spinner("Loading database schema and running migrations") do
            _stdout, stderr, status = Open3.capture3("bin/rails db:schema:load db:migrate")
            if status.success?
              { success: true }
            else
              { success: false, error: "Failed to load schema: #{stderr}" }
            end
          end
          
          # Seed the database
          env = config.respond_to?(:seed_env) && config.seed_env ? { "SEED_DEV_ENV" => "true" } : {}
          with_spinner("Seeding the database") do
            _stdout, stderr, status = Open3.capture3(env, "bin/rails db:seed")
            if status.success?
              { success: true }
            else
              { success: false, error: "Failed to seed database: #{stderr}" }
            end
          end
          
          # Setup test database
          terminate_database_connections("test")
          with_spinner("Setting up test database") do
            _stdout, stderr, status = Open3.capture3({ "RAILS_ENV" => "test" }, "bash", "-c", "bin/rails db:drop db:create db:schema:load > /dev/null 2>&1")
            if status.success?
              { success: true }
            else
              { success: false, error: "Failed to setup test database: #{stderr}" }
            end
          end
          
          # Clear logs and temp files
          with_spinner("Clearing logs and temp files") do
            _stdout, _stderr, status = Open3.capture3("bash", "-c", "bin/rails log:clear tmp:clear > /dev/null 2>&1")
            if status.success?
              { success: true }
            else
              # Don't fail for log clearing
              { success: true }
            end
          end
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
          
          with_spinner("Terminating existing database connections#{rails_env ? " (#{rails_env})" : ""}") do
            stdout, stderr, status = Open3.capture3(env_vars, "bin/rails", "runner", runner_script)
            
            if status.success?
              logger&.debug("Output: #{stdout}") if stdout && !stdout.empty?
              { success: true }
            else
              logger&.debug("Error: #{stderr}") if stderr && !stderr.empty?
              # Don't fail if we can't terminate connections - the database might not exist
              { success: true }
            end
          end
        end
      end
    end
  end
end