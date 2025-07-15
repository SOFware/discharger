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
          self.class.name.demodulize.underscore.humanize
        end

        protected

        def log(message)
          logger.info "[#{self.class.name.demodulize}] #{message}"
        end

        def system!(*args)
          log "Executing #{args.join(" ")}"

          if system(*args)
            log "#{args.join(" ")} succeeded"
          elsif args.first.to_s.include?("docker")
            log "#{args.join(" ")} failed (Docker command)"
          else
            raise "#{args.join(" ")} failed"
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
