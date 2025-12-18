# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class DockerCommand < BaseCommand
        def execute
          # Setup database container if configured
          if database_configured?
            puts "  → Checking database configuration..." unless ENV["QUIET_SETUP"]
            if native_postgresql_available?
              puts "  → Native PostgreSQL detected on port #{native_postgresql_port}, skipping Docker setup" unless ENV["QUIET_SETUP"]
              ENV["DB_PORT"] ||= native_postgresql_port.to_s
            else
              puts "  → No native PostgreSQL found, setting up Docker container..." unless ENV["QUIET_SETUP"]
              ensure_docker_running
              setup_container(
                name: database_config.name || "db-app",
                port: database_config.port || 5432,
                image: "postgres:#{database_config.version || "14"}",
                env: {"POSTGRES_PASSWORD" => database_config.password || "postgres"},
                volume: "#{database_config.name || "db-app"}:/var/lib/postgresql/data",
                internal_port: 5432
              )
            end
          end

          # Setup Redis container if configured
          if redis_configured?
            setup_container(
              name: redis_config.name || "redis-app",
              port: redis_config.port || 6379,
              image: "redis:#{redis_config.version || "latest"}",
              internal_port: 6379
            )
          end
        end

        def can_execute?
          # Only execute if Docker is available and containers are configured
          docker_available? && (database_configured? || redis_configured?)
        end

        def description
          "Setup Docker containers"
        end

        private

        def setup_container(name:, port:, image:, internal_port:, env: {}, volume: nil)
          log "Checking #{name} container"

          if system_quiet("docker ps | grep #{name} > /dev/null 2>&1")
            log "#{name} container is already running"
            return
          end

          # Check if container exists but is stopped
          if system_quiet("docker inspect #{name} > /dev/null 2>&1")
            log "Starting existing #{name} container"
            unless system_quiet("docker start #{name}")
              log "Removing failed #{name} container"
              system_quiet("docker rm -f #{name}")
              create_container(name: name, port: port, image: image, env: env, volume: volume, internal_port: internal_port)
            end
          else
            create_container(name: name, port: port, image: image, env: env, volume: volume, internal_port: internal_port)
          end

          # Verify container is running
          sleep 2
          unless system_quiet("docker ps | grep #{name} > /dev/null 2>&1")
            log "#{name} container failed to start"
            raise "#{name} container failed to start"
          end
        end

        def create_container(name:, port:, image:, internal_port:, env: {}, volume: nil)
          log "Creating new #{name} container"

          cmd = ["docker", "run", "-d", "--name", name, "-p", "#{port}:#{internal_port}"]
          env.each { |k, v| cmd.push("-e", "#{k}=#{v}") }
          cmd.push("-v", volume) if volume
          cmd.push(image)

          system!(*cmd)
        end

        def docker_available?
          return true if system_quiet("which docker > /dev/null 2>&1")

          ["/usr/bin/docker", "/usr/local/bin/docker"].each do |path|
            return true if File.executable?(path)
          end

          false
        end

        def docker_running?
          system_quiet("docker info > /dev/null 2>&1")
        end

        def start_docker_for_platform
          case RUBY_PLATFORM
          when /darwin/
            system_quiet("open -a Docker")
          when /linux/
            if system_quiet("which systemctl > /dev/null 2>&1")
              log "Attempting to start Docker service..."
              system_quiet("sudo systemctl start docker")
            else
              log "Docker service management not available. Please ensure Docker is running."
            end
          else
            log "Unsupported platform for automatic Docker startup: #{RUBY_PLATFORM}"
          end
        end

        def ensure_docker_running
          log "Ensure Docker is running"

          unless docker_running?
            log "Starting Docker..."
            start_docker_for_platform
            sleep 10
            unless docker_running?
              log "Docker is not running. Please start Docker manually."
              return false
            end
          end
          true
        end

        def database_configured?
          config.database&.name
        end

        def redis_configured?
          config.redis&.name
        end

        def database_config
          config.database
        end

        def redis_config
          config.redis
        end

        def native_postgresql_available?
          # If a specific port is configured, ONLY check that port
          # We should not use a native PostgreSQL on a different port
          configured_port = config.database&.port
          if configured_port
            if postgresql_running_on_port?(configured_port)
              @native_pg_port = configured_port
              return true
            end
            # Configured port specified but PostgreSQL not running on it
            return false
          end

          # No specific port configured, check common PostgreSQL ports
          [5432, 5433].each do |port|
            if postgresql_running_on_port?(port)
              @native_pg_port = port
              return true
            end
          end
          false
        end

        def native_postgresql_port
          @native_pg_port || 5432
        end

        def postgresql_running_on_port?(port)
          # Method 1: Try pg_isready if available
          if system_quiet("which pg_isready > /dev/null 2>&1")
            return system_quiet("pg_isready -h localhost -p #{port} > /dev/null 2>&1")
          end

          # Method 2: Try psql connection
          if system_quiet("which psql > /dev/null 2>&1")
            return system_quiet("psql -h localhost -p #{port} -U postgres -c '\\q' > /dev/null 2>&1")
          end

          false
        end
      end
    end
  end
end
