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

        def log(message, emoji: nil)
          return unless logger
          class_name = self.class.name || "AnonymousCommand"
          prefix = emoji ? "#{emoji} " : ""
          logger.info "#{prefix}[#{class_name.demodulize}] #{message}"
        end

        def with_spinner(message)
          if ENV['CI'] || ENV['NO_SPINNER'] || !$stdout.tty?
            result = yield
            # Handle error case when spinner is disabled
            if result.is_a?(Hash) && !result[:success] && result[:raise_error] != false
              raise result[:error]
            end
            return result
          end
          
          require 'rainbow'
          spinner_chars = %w[⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏]
          spinner_thread = nil
          stop_spinner = false
          
          begin
            # Print initial message
            print Rainbow("◯ #{message}").cyan
            $stdout.flush
            
            # Start spinner in background thread
            spinner_thread = Thread.new do
              i = 0
              until stop_spinner
                print "\r#{Rainbow(spinner_chars[i % spinner_chars.length]).cyan} #{Rainbow(message).cyan}"
                $stdout.flush
                sleep 0.1
                i += 1
              end
            end
            
            # Execute the block
            result = yield
            
            # Stop spinner
            stop_spinner = true
            spinner_thread&.join(0.1)
            
            # Clear line and print result
            if result.is_a?(Hash)
              if result[:success]
                puts "\r#{Rainbow(result[:message] || '✓').green} #{message}"
              else
                puts "\r#{Rainbow(result[:message] || '✗').red} #{message}"
                raise result[:error] if result[:error] && result[:raise_error] != false
              end
            else
              puts "\r#{Rainbow('✓').green} #{message}"
            end
            
            result
          rescue
            stop_spinner = true
            spinner_thread&.join(0.1)
            puts "\r#{Rainbow('✗').red} #{message}"
            raise
          ensure
            stop_spinner = true
            spinner_thread&.kill if spinner_thread&.alive?
          end
        end

        def simple_action(message)
          return yield if ENV['CI'] || ENV['NO_SPINNER'] || !$stdout.tty?
          
          require 'rainbow'
          print Rainbow("  → #{message}...").cyan
          $stdout.flush
          
          begin
            result = yield
            puts Rainbow(" ✓").green
            result
          rescue
            puts Rainbow(" ✗").red
            raise
          end
        end

        def system!(*args)
          require 'open3'
          command_str = args.join(" ")
          
          # Create a more readable message for the spinner
          spinner_message = if command_str.length > 80
            if args.first.is_a?(Hash)
              # Skip env hash in display
              cmd_args = args[1..-1]
              base_cmd = cmd_args.take(3).join(" ")
              "Executing #{base_cmd}..."
            else
              base_cmd = args.take(3).join(" ")
              "Executing #{base_cmd}..."
            end
          else
            "Executing #{command_str}"
          end
          
          result = with_spinner(spinner_message) do
            stdout, stderr, status = Open3.capture3(*args)
            
            if status.success?
              # Log output if there is any (for debugging)
              logger&.debug("Output: #{stdout}") if stdout && !stdout.empty?
              { success: true, message: "✓" }
            elsif args.first.to_s.include?("docker")
              logger&.debug("Error: #{stderr}") if stderr && !stderr.empty?
              { success: false, message: "✗ (Docker command failed)", raise_error: false }
            else
              { success: false, message: "✗", error: "#{command_str} failed: #{stderr}" }
            end
          end
          
          # Handle the case when spinner is disabled
          if result.is_a?(Hash) && !result[:success] && result[:raise_error] != false
            raise result[:error]
          end
          
          result
        end

        def system_quiet(*args)
          require 'open3'
          stdout, _stderr, status = Open3.capture3(*args)
          logger&.debug("Quietly executed #{args.join(" ")} - success: #{status.success?}")
          logger&.debug("Output: #{stdout}") if stdout && !stdout.empty? && logger
          status.success?
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
