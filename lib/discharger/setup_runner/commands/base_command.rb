# frozen_string_literal: true

module Discharger
  module SetupRunner
    module Commands
      class BaseCommand
        attr_reader :config, :app_root, :logger

        def initialize(config, app_root, logger)
          @config = config
          @app_root = app_root
          @logger = logger
        end

        def execute
          raise NotImplementedError, "#{self.class} must implement #execute"
        end

        def can_execute?
          true
        end

        def description
          class_name = self.class.name || "AnonymousCommand"
          class_name.demodulize.underscore.humanize
        end

        protected

        def log(message)
          return unless logger
          class_name = self.class.name || "AnonymousCommand"
          logger.info "[#{class_name.demodulize}] #{message}"
        end

        def system!(*args)
          require 'open3'
          log "Executing #{args.join(" ")}"

          stdout, stderr, status = Open3.capture3(*args)
          
          if status.success?
            log "#{args.join(" ")} succeeded"
            # Log output if there is any (for debugging)
            logger&.debug("Output: #{stdout}") if stdout && !stdout.empty?
          elsif args.first.to_s.include?("docker")
            log "#{args.join(" ")} failed (Docker command)"
            logger&.debug("Error: #{stderr}") if stderr && !stderr.empty?
          else
            raise "#{args.join(" ")} failed: #{stderr}"
          end
        end

        def ask_to_install(description)
          puts "You do not currently use #{description}.\n ===> If you want to, type Y\nOtherwise hit any key to ignore."
          if gets.chomp == "Y"
            yield
          end
        end

        def proceed_with(task)
          puts "Proceed with #{task}?\n ===> Type Y to proceed\nOtherwise hit any key to ignore."
          if gets.chomp == "Y"
            yield
          end
        end
      end
    end
  end
end
