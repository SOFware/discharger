module Discharger
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :setup_path,
        type: :string,
        default: "bin/setup",
        desc: "Path where the setup script should be created"

      class_option :setup_only,
        type: :boolean,
        default: false,
        desc: "Only (re)generate the setup script, leaving config/setup.yml and the initializer alone"

      def copy_initializer
        return if options[:setup_only]

        template "discharger_initializer.rb", "config/initializers/discharger.rb"
      end

      def create_setup_script
        template "setup", options[:setup_path]
        chmod options[:setup_path], 0o755
      end

      def create_sample_setup_yml
        return if options[:setup_only]

        template "setup.yml", "config/setup.yml"
      end
    end
  end
end
