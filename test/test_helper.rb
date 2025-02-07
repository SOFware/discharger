# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

if ENV["CI"]
  require "simplecov"
end

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

require "discharger/helpers/sys_helper"
require "discharger"
require "discharger/task"

require "debug"

require "bundler/setup"
require "minitest/autorun"
require "minitest/mock"
require "rake"

# Add the lib directory to the load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

# Require any support files
Dir[File.expand_path("support/**/*.rb", __dir__)].each { |f| require f }

# Configure minitest reporter if you want prettier output
require "minitest/reporters"
Minitest::Reporters.use! [Minitest::Reporters::DefaultReporter.new(color: true)]

# Add near the top of the file
TEST_GIT_COMMANDS = ENV["TEST_GIT_COMMANDS"] == "true"

# Reset Rake tasks before each test
module Minitest
  class Test
    def setup
      Rake::Task.clear
      super
    end
  end
end
