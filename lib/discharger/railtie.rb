module Discharger
  class Railtie < ::Rails::Railtie
    # Prepend bin/pg-tools to PATH so Docker-aware pg_dump/psql wrappers are used
    # This runs before any rake tasks execute, ensuring Rails uses the wrappers
    initializer "discharger.pg_tools_path", before: :load_config_initializers do
      pg_tools_path = Rails.root.join("bin", "pg-tools").to_s
      if File.directory?(pg_tools_path) && !ENV["PATH"].to_s.include?(pg_tools_path)
        ENV["PATH"] = "#{pg_tools_path}:#{ENV["PATH"]}"
      end
    end

    config.after_initialize do |app|
      if Rails.env.development? && Discharger.slack_token.nil?
        warn "Your application Discharger.slack_token must be set."
      end
    end
  end
end
