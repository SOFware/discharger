module Discharger
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      def copy_initializer
        template "discharger_initializer.rb", "config/initializers/discharger.rb"
      end
    end
  end
end
