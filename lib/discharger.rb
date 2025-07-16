require "discharger/version"
require "discharger/railtie"
require "discharger/setup_runner"

module Discharger
  class << self
    attr_accessor :slack_token

    def configure
      yield self
    end
  end
end
