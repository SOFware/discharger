# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class PgToolsCommand < BaseCommand
        TOOLS = %w[pg_dump psql].freeze

        def description
          "Setting up PostgreSQL tools wrappers"
        end

        def can_execute?
          config.respond_to?(:database) && config.database&.name.present?
        end

        def execute
          create_pg_tools_directory
          TOOLS.each { |tool| create_wrapper(tool) }
          create_envrc_if_needed
        end

        private

        def container_name
          config.database.name
        end

        def create_pg_tools_directory
          FileUtils.mkdir_p(File.join(app_root, "bin", "pg-tools"))
        end

        def create_wrapper(tool)
          wrapper_path = File.join(app_root, "bin", "pg-tools", tool)
          File.write(wrapper_path, wrapper_content(tool))
          FileUtils.chmod(0o755, wrapper_path)
          log "Created bin/pg-tools/#{tool}"
        end

        def wrapper_content(tool)
          if tool == "pg_dump"
            pg_dump_wrapper_content
          else
            generic_wrapper_content(tool)
          end
        end

        def pg_dump_wrapper_content
          <<~BASH
            #!/usr/bin/env bash
            set -e

            CONTAINER="#{container_name}"

            # Docker first: use container's pg_dump if running
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
              echo "Using pg_dump from Docker container: $CONTAINER" >&2

              # Parse arguments to handle --file option specially
              # When running in Docker, we need to output to stdout and redirect locally
              OUTPUT_FILE=""
              HAS_USER=""
              ARGS=()
              while [[ $# -gt 0 ]]; do
                case $1 in
                  --file)
                    OUTPUT_FILE="$2"
                    shift 2
                    ;;
                  --file=*)
                    OUTPUT_FILE="${1#*=}"
                    shift
                    ;;
                  -f)
                    OUTPUT_FILE="$2"
                    shift 2
                    ;;
                  -U|--username|--username=*)
                    HAS_USER="1"
                    ARGS+=("$1")
                    shift
                    ;;
                  *)
                    ARGS+=("$1")
                    shift
                    ;;
                esac
              done

              # Default to postgres user if not specified (container runs as root)
              if [[ -z "$HAS_USER" ]]; then
                ARGS=("-U" "postgres" "${ARGS[@]}")
              fi

              if [[ -n "$OUTPUT_FILE" ]]; then
                # Run pg_dump in container, output to stdout, redirect to local file
                docker exec -i "$CONTAINER" pg_dump "${ARGS[@]}" > "$OUTPUT_FILE"
              else
                # No file output, just exec normally
                exec docker exec -i "$CONTAINER" pg_dump "${ARGS[@]}"
              fi
              exit 0
            fi

            # Fallback to system pg_dump
            exec pg_dump "$@"
          BASH
        end

        def generic_wrapper_content(tool)
          <<~BASH
            #!/usr/bin/env bash
            set -e

            CONTAINER="#{container_name}"

            # Docker first: use container's #{tool} if running
            if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
              echo "Using #{tool} from Docker container: $CONTAINER" >&2
              exec docker exec -i "$CONTAINER" #{tool} "$@"
            fi

            # Fallback to system #{tool}
            exec #{tool} "$@"
          BASH
        end

        def create_envrc_if_needed
          envrc_path = File.join(app_root, ".envrc")
          if File.exist?(envrc_path)
            # Don't overwrite existing .envrc, but suggest adding PATH if not present
            unless File.read(envrc_path).include?("bin/pg-tools")
              log "Note: Add 'PATH_add bin/pg-tools' to existing .envrc for shell access"
            end
          else
            File.write(envrc_path, "PATH_add bin/pg-tools\n")
            log "Created .envrc (run 'direnv allow' to enable for shell access)"
          end
        end
      end
    end
  end
end
