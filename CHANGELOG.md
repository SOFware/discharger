# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.2.12] - Unreleased

## [0.2.11] - 2025-07-16

### Added

- Added fragment_directory attribute for task configuration.

### Fixed

- Added SetupRunner module for automated development environment setup
  - Configuration-driven setup process via YAML files
  - Built-in commands for common tasks (Brew, Bundler, environment files)
  - Custom command support with conditional execution
  - Safe condition evaluation using Prism parser (no eval)
  - Extensible command registry for adding new setup commands
- Updated Rails generator to create setup script and configuration
  - `rails generate discharger:install` now creates `bin/setup` script
  - Creates `config/setup.yml` with example configuration
  - Customizable setup script location via `--setup_path` option
- Added new built-in setup commands:
  - AsdfCommand: Manages tool versions using asdf
  - ConfigCommand: Copies configuration files from examples
  - DatabaseCommand: Sets up Rails databases (development and test)
  - DockerCommand: Manages Docker containers for services
  - GitCommand: Configures git settings and hooks
  - YarnCommand: Installs JavaScript dependencies (Yarn/NPM)
- Added post-install message to guide users to run the generator

### Changed

- Added an automatic release github action.
- Updated `system!` in BaseCommand to use Open3 for better output control
- Added `prism` gem dependency for safe condition evaluation
- Improved DatabaseCommand to terminate existing database connections before dropping
  - Uses ActiveRecord connection instead of psql to avoid password prompts
  - Works with any Rails-supported PostgreSQL setup including Docker
  - Gracefully handles non-PostgreSQL databases
- Enhanced SetupRunner with visual feedback
  - Added animated spinners for long-running commands
  - Colorized output for better readability
  - Clear success/failure indicators for each command
  - Progress indicators that work in CI environments
  - Cleaner output for database operations (no more verbose Rails runner scripts)
  - Smart truncation of long commands in spinner messages
