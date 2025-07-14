require "strscan"
require_relative "markdown"

module Reissue
  class Parser
    def self.parse(changelog)
      new(changelog).parse
    end

    def initialize(changelog)
      @changelog = changelog
    end

    def parse
      Markdown.parse(@changelog).to_h
    end
  end
end
