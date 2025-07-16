# frozen_string_literal: true

require_relative "base_command"

module Discharger
  module SetupRunner
    module Commands
      class AsdfCommand < BaseCommand
        def execute
          log "Install tool-versions dependencies via ASDF"

          unless system_quiet("which asdf")
            log "asdf not installed. Run `brew install asdf` if you want bin/setup to ensure versions are up-to-date"
            return
          end

          tools_versions_file = File.join(app_root, ".tool-versions")
          return log("No .tool-versions file found") unless File.exist?(tools_versions_file)

          dependencies = File.read(tools_versions_file).split("\n")
          installables = []

          # Check for nodejs plugin
          unless system_quiet("asdf plugin list | grep nodejs")
            node_deps = dependencies.select { |item| item.match?(/node/) }
            if node_deps.any?
              ask_to_install "asdf to manage Node JS" do
                installables.concat(node_deps)
                system! "asdf plugin add nodejs https://github.com/asdf-vm/asdf-nodejs.git"
              end
            end
          end

          # Check for ruby plugin
          unless system_quiet("asdf plugin list | grep ruby")
            ruby_deps = dependencies.select { |item| item.match?(/ruby/) }
            if ruby_deps.any?
              ask_to_install "asdf to manage Ruby" do
                installables.concat(ruby_deps)
                system! "asdf plugin add ruby https://github.com/asdf-vm/asdf-ruby.git"
              end
            end
          end

          # Install all versions
          installables.each do |name_version|
            system! "asdf install #{name_version}"
          end
        end

        def can_execute?
          File.exist?(File.join(app_root, ".tool-versions"))
        end

        def description
          "Install tool versions with asdf"
        end
      end
    end
  end
end
