# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require "simplecov"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [File.expand_path("../test/dummy/db/migrate", __dir__)]
require "rails/test_help"

# Load fixtures from the engine
if ActiveSupport::TestCase.respond_to?(:fixture_paths=)
  ActiveSupport::TestCase.fixture_paths = [File.expand_path("fixtures", __dir__)]
  ActionDispatch::IntegrationTest.fixture_paths = ActiveSupport::TestCase.fixture_paths
  ActiveSupport::TestCase.file_fixture_path = File.expand_path("fixtures", __dir__) + "/files"
  ActiveSupport::TestCase.fixtures :all
end

require "discharger"
require "discharger/task"

require "debug"
require "open3"

# Swaps Open3.capture3 for the duration of a block, restoring the original
# even when the block raises. Returns the argv arrays capture3 was called
# with, so callers can assert on the executed command.
module Capture3Stubbing
  def stub_capture3(stdout: "", stderr: "", success: true)
    calls = []
    original = Open3.method(:capture3)
    status = Object.new
    status.define_singleton_method(:success?) { success }
    Open3.define_singleton_method(:capture3) do |*args|
      calls << args
      [stdout, stderr, status]
    end
    yield
    calls
  ensure
    Open3.define_singleton_method(:capture3, original)
  end
end
