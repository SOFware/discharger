require "discharger/version"
require "discharger/railtie"

module Discharger
  class << self
    attr_accessor :slack_token
  end
end
