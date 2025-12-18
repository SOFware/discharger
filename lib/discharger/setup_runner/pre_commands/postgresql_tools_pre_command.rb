# frozen_string_literal: true

require_relative "base_pre_command"

module Discharger
  module SetupRunner
    module PreCommands
      # Ensures PostgreSQL client tools (pg_dump, psql) are installed.
      # These tools are needed for database operations like db:structure:dump.
      class PostgresqlToolsPreCommand < BasePreCommand
        def execute
          if command_exists?("pg_dump")
            log "PostgreSQL client tools found"
            return true
          end

          log "PostgreSQL client tools (pg_dump) not found."
          pg_version = config.dig("database", "version") || "14"

          if platform_darwin?
            install_via_homebrew(pg_version)
          elsif platform_linux?
            install_via_apt(pg_version)
          else
            log "WARNING: Unsupported platform for PostgreSQL client tools installation"
            false
          end
        end

        def description
          "Ensure PostgreSQL client tools are installed"
        end

        private

        def install_via_homebrew(version)
          log "Installing PostgreSQL #{version} client tools via Homebrew..."
          if system("brew install postgresql@#{version}")
            log "PostgreSQL #{version} client tools installed successfully"
            true
          else
            log "WARNING: Failed to install PostgreSQL client tools"
            log "Please install manually: brew install postgresql@#{version}"
            false
          end
        end

        def install_via_apt(version)
          unless command_exists?("apt-get")
            log "WARNING: apt-get not found"
            log "Please install postgresql-client-#{version} using your system's package manager"
            return false
          end

          log "Installing PostgreSQL #{version} client tools via apt..."
          if system("sudo apt-get install -y postgresql-client-#{version}")
            # Set up alternatives for the installed version
            priority = version.to_i * 10
            system("sudo update-alternatives --install /usr/bin/pg_dump pg_dump /usr/lib/postgresql/#{version}/bin/pg_dump #{priority}")
            system("sudo update-alternatives --install /usr/bin/psql psql /usr/lib/postgresql/#{version}/bin/psql #{priority}")
            log "PostgreSQL #{version} client tools installed successfully"
            true
          else
            log "WARNING: Failed to install PostgreSQL client tools"
            log "Please install manually: sudo apt-get install postgresql-client-#{version}"
            false
          end
        end
      end
    end
  end
end
