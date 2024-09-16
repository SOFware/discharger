module Discharger
  class Railtie < ::Rails::Railtie
    config.after_initialize do |app|
      if Rails.env.development? && Discharger.slack_token.nil?
        warn "Your application Discharger.slack_token must be set."
      end
    end
  end
end
