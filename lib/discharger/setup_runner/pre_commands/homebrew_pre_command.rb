# frozen_string_literal: true

require_relative "base_pre_command"

module Discharger
  module SetupRunner
    module PreCommands
      # Ensures Homebrew/Linuxbrew is installed.
      # This must run before `brew bundle` can install Brewfile dependencies.
      class HomebrewPreCommand < BasePreCommand
        HOMEBREW_INSTALL_URL = "https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh"
        LINUXBREW_PATH = "/home/linuxbrew/.linuxbrew/bin"

        def execute
          if command_exists?("brew")
            log "Homebrew found at: #{`which brew`.strip}"
            return true
          end

          log "Homebrew not found. Installing..."

          if platform_darwin?
            install_homebrew_macos
          elsif platform_linux?
            install_homebrew_linux
          else
            log "WARNING: Unsupported platform for automatic Homebrew installation"
            log "Please install Homebrew manually: https://brew.sh"
            return false
          end

          verify_installation
        end

        def description
          "Ensure Homebrew is installed"
        end

        private

        def install_homebrew_macos
          log "Installing Homebrew for macOS..."
          system(%(/bin/bash -c "$(curl -fsSL #{HOMEBREW_INSTALL_URL})"))
        end

        def install_homebrew_linux
          log "Installing Linuxbrew for Linux..."
          system(%(/bin/bash -c "$(curl -fsSL #{HOMEBREW_INSTALL_URL})"))

          # Add Linuxbrew to PATH for current session
          if File.exist?(LINUXBREW_PATH)
            ENV["PATH"] = "#{LINUXBREW_PATH}:#{ENV["PATH"]}"
            log "Added Linuxbrew to PATH"
          end
        end

        def verify_installation
          unless command_exists?("brew")
            log "ERROR: Homebrew installation failed or not in PATH"
            log "Please install Homebrew manually and ensure it's in your PATH"
            return false
          end
          log "Homebrew installed successfully"
          true
        end
      end
    end
  end
end
