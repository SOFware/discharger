module Discharger
  class Railtie < ::Rails::Railtie
    config.before_configuration do
      if ENV["SLACK_API_TOKEN_RELEASES"].nil?
        raise "SLACK_API_TOKEN_RELEASES must be set in the environment"
      end
    end
  end
end
