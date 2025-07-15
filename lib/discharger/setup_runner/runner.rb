# frozen_string_literal: true

require "fileutils"
require "logger"
require_relative "command_factory"

module Discharger
  module SetupRunner
    class Error < StandardError; end

    class Runner
      attr_reader :config, :app_root, :logger, :command_factory

      def initialize(config, app_root = nil, logger = nil)
        @config = config
        @app_root = app_root || Dir.pwd
        @logger = logger || Logger.new($stdout)
        @command_factory = CommandFactory.new(config, app_root, logger)
      end

      def run
        require 'rainbow'
        unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
          puts Rainbow("\n🚀 Starting setup for #{config.app_name}").bright.blue
          puts Rainbow("=" * 50).blue
        end

        FileUtils.chdir app_root do
          execute_commands
        end

        unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
          puts Rainbow("\n✅ Setup completed successfully!").bright.green
        end
      rescue => e
        unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
          puts Rainbow("\n❌ Setup failed: #{e.message}").bright.red
        end
        raise Error, e.message
      end

      def add_command(command)
        commands << command
      end

      def remove_command(command_name)
        commands.reject! { |cmd| cmd.class.name.demodulize.underscore == command_name.to_s }
      end

      def replace_command(command_name, new_command)
        remove_command(command_name)
        add_command(new_command)
      end

      def insert_command_before(target_command_name, new_command)
        target_index = commands.find_index { |cmd| cmd.class.name.demodulize.underscore == target_command_name.to_s }
        if target_index
          commands.insert(target_index, new_command)
        else
          add_command(new_command)
        end
      end

      def insert_command_after(target_command_name, new_command)
        target_index = commands.find_index { |cmd| cmd.class.name.demodulize.underscore == target_command_name.to_s }
        if target_index
          commands.insert(target_index + 1, new_command)
        else
          add_command(new_command)
        end
      end

      private

      def commands
        @commands ||= command_factory.create_all_commands
      end

      def execute_commands
        commands.each do |command|
          execute_command(command)
        end
      end

      def execute_command(command)
        unless command.can_execute?
          unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
            require 'rainbow'
            puts Rainbow("⏭️  Skipping #{command.description} (prerequisites not met)").yellow
          end
          return
        end

        unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
          puts Rainbow("\n▶️  #{command.description}").bright
        end
        command.execute
      rescue => e
        unless ENV['QUIET_SETUP'] || ENV['DISABLE_OUTPUT']
          require 'rainbow'
          puts Rainbow("❌ Command #{command.description} failed: #{e.message}").red
        end
        raise e
      end

      def log(message)
        logger.info message
      end
    end
  end
end