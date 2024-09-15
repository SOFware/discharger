module Discharger
  class Railtie < ::Rails::Railtie
    config.after_initialize do |app|
      if Rails.env.development? && Discharger.slack_token.nil?
        raise "Your application Discharger.slack_token must be set in the environment"
      end
    end
  end
end
