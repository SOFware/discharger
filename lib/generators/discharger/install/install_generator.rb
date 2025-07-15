module Discharger
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      class_option :setup_path, 
                   type: :string, 
                   default: "bin/setup",
                   desc: "Path where the setup script should be created"

      def copy_initializer
        template "discharger_initializer.rb", "config/initializers/discharger.rb"
      end

      def create_setup_script
        template "setup", options[:setup_path]
        chmod options[:setup_path], 0755
      end

      def create_sample_setup_yml
        template "setup.yml", "config/setup.yml"
      end
    end
  end
end