# frozen_string_literal: true

# Standalone loader for Discharger::SetupRunner::PrerequisitesLoader
# This can be required before Rails loads to set up environment variables
# and system dependencies.
#
# Usage in bin/setup:
#   require "discharger/prerequisites"
#   Discharger::SetupRunner::PrerequisitesLoader.run("config/setup.yml")
#
require_relative "setup_runner/pre_commands/base_pre_command"
require_relative "setup_runner/pre_commands/homebrew_pre_command"
require_relative "setup_runner/pre_commands/postgresql_tools_pre_command"
require_relative "setup_runner/pre_commands/pre_command_registry"
require_relative "setup_runner/prerequisites_loader"
