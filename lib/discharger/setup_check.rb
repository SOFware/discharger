# frozen_string_literal: true

require_relative "version"

module Discharger
  class SetupCheck
    TEMPLATE = File.expand_path("../generators/discharger/install/templates/setup", __dir__)
    GENERATE = "bin/rails generate discharger:install --setup-only --force"

    def self.run(setup_path = "bin/setup", out: $stdout)
      new(setup_path).run(out: out)
    end

    def initialize(setup_path = "bin/setup")
      @setup_path = setup_path
    end

    def run(out: $stdout)
      unless File.exist?(@setup_path)
        out.puts "#{@setup_path} not found. Generate it: #{generate_command}"
        return false
      end

      if (line = first_differing_line)
        out.puts "#{@setup_path} differs from the discharger #{VERSION} template at line #{line}. " \
          "Regenerate it: #{generate_command}"
        return false
      end

      out.puts "#{@setup_path} matches the discharger #{VERSION} template"
      true
    end

    private

    def first_differing_line
      actual = File.readlines(@setup_path)
      expected = File.readlines(TEMPLATE)
      return if actual == expected

      (actual.zip(expected).index { |a, e| a != e } || actual.size) + 1
    end

    def generate_command
      return GENERATE if @setup_path == "bin/setup"

      "#{GENERATE} --setup_path=#{@setup_path}"
    end
  end
end
