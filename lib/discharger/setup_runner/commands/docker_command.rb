# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class DockerCommand < BaseCommand
        def execute
          log "Ensure Docker is running"
          
          unless system_quiet("docker info > /dev/null 2>&1")
            log "Starting Docker..."
            system_quiet("open -a Docker")
            sleep 10
            unless system_quiet("docker info > /dev/null 2>&1")
              log "Docker is not running. Please start Docker manually."
              return
            end
          end
          
          # Setup database container if configured
          if config.respond_to?(:database) && config.database
            setup_container(
              name: config.database.name || "db-app",
              port: config.database.port || 5432,
              image: "postgres:#{config.database.version || '14'}",
              env: { "POSTGRES_PASSWORD" => config.database.password || "postgres" },
              volume: "#{config.database.name || 'db-app'}:/var/lib/postgresql/data",
              internal_port: 5432
            )
          end
          
          # Setup Redis container if configured
          if config.respond_to?(:redis) && config.redis
            setup_container(
              name: config.redis.name || "redis-app",
              port: config.redis.port || 6379,
              image: "redis:#{config.redis.version || 'latest'}",
              internal_port: 6379
            )
          end
        end
        
        def can_execute?
          # Only execute if Docker is available and containers are configured
          system_quiet("which docker") && (
            (config.respond_to?(:database) && config.database) ||
            (config.respond_to?(:redis) && config.redis)
          )
        end
        
        def description
          "Setup Docker containers"
        end
        
        private
        
        def setup_container(name:, port:, image:, env: {}, volume: nil, internal_port:)
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
        
        def create_container(name:, port:, image:, env: {}, volume: nil, internal_port:)
          log "Creating new #{name} container"
          
          cmd = ["docker", "run", "-d", "--name", name, "-p", "#{port}:#{internal_port}"]
          env.each { |k, v| cmd.push("-e", "#{k}=#{v}") }
          cmd.push("-v", volume) if volume
          cmd.push(image)
          
          system!(*cmd)
        end
      end
    end
  end
end