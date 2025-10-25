# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class DockerCommand < BaseCommand
        def execute
          # Setup database container if configured
          if config.respond_to?(:database) && config.database
            if native_postgresql_available?
              log "Native PostgreSQL detected on port #{native_postgresql_port}, skipping Docker container setup"
              ENV["DB_PORT"] ||= native_postgresql_port.to_s
            else
              ensure_docker_running
              setup_container(
                name: config.database.name || "db-app",
                port: config.database.port || 5432,
                image: "postgres:#{config.database.version || "14"}",
                env: {"POSTGRES_PASSWORD" => config.database.password || "postgres"},
                volume: "#{config.database.name || "db-app"}:/var/lib/postgresql/data",
                internal_port: 5432
              )
            end
          end

          # Setup Redis container if configured
          if config.respond_to?(:redis) && config.redis
            setup_container(
              name: config.redis.name || "redis-app",
              port: config.redis.port || 6379,
              image: "redis:#{config.redis.version || "latest"}",
              internal_port: 6379
            )
          end
        end

        def can_execute?
          # Only execute if Docker is available and containers are configured
          docker_available? && (
            (config.respond_to?(:database) && config.database) ||
            (config.respond_to?(:redis) && config.redis)
          )
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

        def native_postgresql_available?
          # Check common PostgreSQL ports
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
