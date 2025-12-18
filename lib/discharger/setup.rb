# frozen_string_literal: true

require "fileutils"
require "pathname"

# Unified entry point for Discharger setup.
# Handles both pre-Rails prerequisites and post-Rails setup commands.
#
# Usage in bin/setup:
#   require "discharger/setup"
#   Discharger::Setup.run("config/setup.yml")
#
# This will automatically:
# 1. Load bundler/setup (activates correct gem versions)
# 2. Run pre_steps (before Rails loads) - env vars, homebrew, etc.
# 3. Initialize Rails
# 4. Run regular setup steps and custom_steps
#
module Discharger
  class Setup
    attr_reader :config_path, :app_root

    def initialize(config_path, app_root: nil)
      @config_path = config_path
      @app_root = app_root || Dir.pwd
    end

    def self.run(config_path = "config/setup.yml", app_root: nil)
      new(config_path, app_root: app_root).run
    end

    def run
      FileUtils.chdir(app_root) do
        validate_environment
        print_header

        # Phase 1: Load bundler first (activates correct gem versions)
        # This must happen before we parse YAML to avoid psych version conflicts
        load_bundler

        # Phase 2: Pre-Rails setup (env vars, system dependencies)
        # These run AFTER bundler but BEFORE Rails loads
        run_prerequisites

        # Phase 3: Load Rails (uses env vars from phase 2)
        load_rails

        # Phase 4: Run Discharger commands (after Rails loads)
        run_setup_commands

        print_footer
      end
    end

    private

    def validate_environment
      unless File.exist?("Gemfile")
        puts "No Gemfile found. Please run this script from the root of your Rails application."
        exit 1
      end

      unless File.exist?(config_path)
        puts "No #{config_path} found. Please run 'rails generate discharger:install' first."
        exit 1
      end
    end

    def print_header
      puts "== Running Discharger setup =="
      puts "Configuration loaded from: #{config_path}"
    end

    def print_footer
      puts "\n== Setup completed successfully! =="
    end

    def load_bundler
      require "bundler/setup"
    end

    def run_prerequisites
      puts "\n== Setting up prerequisites =="
      require_relative "prerequisites"
      SetupRunner::PrerequisitesLoader.run(config_path)
    end

    def load_rails
      # Load Rails from the standard location
      rails_config = File.join(app_root, "config", "application.rb")
      if File.exist?(rails_config)
        require rails_config
        Rails.application.initialize!
      else
        puts "Warning: config/application.rb not found. Skipping Rails initialization."
      end
    end

    def run_setup_commands
      require_relative "../discharger"
      SetupRunner.run(config_path)
    end
  end
end
