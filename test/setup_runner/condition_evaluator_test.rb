require "test_helper"
require "discharger/setup_runner/condition_evaluator"

class ConditionEvaluatorTest < ActiveSupport::TestCase
  def evaluator
    Discharger::SetupRunner::ConditionEvaluator
  end

  test "returns true for nil condition" do
    assert evaluator.evaluate(nil)
  end

  test "returns true for empty string condition" do
    assert evaluator.evaluate("")
    assert evaluator.evaluate("   ")
  end

  test "evaluates simple true condition" do
    assert evaluator.evaluate("true")
  end

  test "evaluates simple false condition" do
    refute evaluator.evaluate("false")
  end

  test "evaluates AND conditions" do
    assert evaluator.evaluate("true && true")
    refute evaluator.evaluate("true && false")
    refute evaluator.evaluate("false && true")
    refute evaluator.evaluate("false && false")
  end

  test "evaluates OR conditions" do
    assert evaluator.evaluate("true || true")
    assert evaluator.evaluate("true || false")
    assert evaluator.evaluate("false || true")
    refute evaluator.evaluate("false || false")
  end

  test "evaluates ENV variable access" do
    ENV["TEST_VAR"] = "test_value"

    assert_equal "test_value", evaluator.evaluate("ENV['TEST_VAR']")
    assert_nil evaluator.evaluate("ENV['NON_EXISTENT_VAR']")
  ensure
    ENV.delete("TEST_VAR")
  end

  test "evaluates ENV variable comparisons" do
    ENV["TEST_VAR"] = "production"

    assert evaluator.evaluate("ENV['TEST_VAR'] == 'production'")
    refute evaluator.evaluate("ENV['TEST_VAR'] == 'development'")
    assert evaluator.evaluate("ENV['TEST_VAR'] != 'development'")
    refute evaluator.evaluate("ENV['TEST_VAR'] != 'production'")
  ensure
    ENV.delete("TEST_VAR")
  end

  test "evaluates File.exist? conditions" do
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, "test.txt")
      File.write(test_file, "test")

      assert evaluator.evaluate("File.exist?('#{test_file}')")
      refute evaluator.evaluate("File.exist?('#{File.join(dir, "non_existent.txt")}')")
    end
  end

  test "evaluates File.directory? conditions" do
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, "test.txt")
      File.write(test_file, "test")

      assert evaluator.evaluate("File.directory?('#{dir}')")
      refute evaluator.evaluate("File.directory?('#{test_file}')")
    end
  end

  test "evaluates File.file? conditions" do
    Dir.mktmpdir do |dir|
      test_file = File.join(dir, "test.txt")
      File.write(test_file, "test")

      assert evaluator.evaluate("File.file?('#{test_file}')")
      refute evaluator.evaluate("File.file?('#{dir}')")
    end
  end

  test "evaluates Dir.exist? conditions" do
    Dir.mktmpdir do |dir|
      assert evaluator.evaluate("Dir.exist?('#{dir}')")
      refute evaluator.evaluate("Dir.exist?('/non/existent/directory')")
    end
  end

  test "evaluates complex conditions" do
    ENV["RAILS_ENV"] = "test"
    Dir.mktmpdir do |dir|
      config_file = File.join(dir, "config.yml")
      File.write(config_file, "test: true")

      condition = "ENV['RAILS_ENV'] == 'test' && File.exist?('#{config_file}')"
      assert evaluator.evaluate(condition)

      condition = "ENV['RAILS_ENV'] == 'production' || File.exist?('#{config_file}')"
      assert evaluator.evaluate(condition)

      condition = "ENV['RAILS_ENV'] == 'production' && File.exist?('#{config_file}')"
      refute evaluator.evaluate(condition)
    end
  ensure
    ENV.delete("RAILS_ENV")
  end

  test "evaluates parentheses conditions" do
    assert evaluator.evaluate("(true)")
    refute evaluator.evaluate("(false)")
    assert evaluator.evaluate("(true && true)")
    assert evaluator.evaluate("(true || false)")
  end

  test "blocks unsafe ENV methods" do
    assert_equal false, evaluator.evaluate("ENV.clear")
    assert_equal false, evaluator.evaluate("ENV.delete('PATH')")
  end

  test "blocks unsafe File methods" do
    assert_equal false, evaluator.evaluate("File.delete('test.txt')")
    assert_equal false, evaluator.evaluate("File.write('test.txt', 'content')")
    assert_equal false, evaluator.evaluate("File.chmod(0777, 'test.txt')")
  end

  test "blocks unsafe Dir methods" do
    assert_equal false, evaluator.evaluate("Dir.mkdir('test')")
    assert_equal false, evaluator.evaluate("Dir.rmdir('test')")
  end

  test "blocks system calls" do
    assert_equal false, evaluator.evaluate("system('rm -rf /')")
    assert_equal false, evaluator.evaluate("exec('ls')")
    assert_equal false, evaluator.evaluate("spawn('echo test')")
  end

  test "blocks backtick commands" do
    assert_equal false, evaluator.evaluate("`ls`")
    assert_equal false, evaluator.evaluate("%x{ls}")
  end

  test "blocks unsafe constant access" do
    assert_equal false, evaluator.evaluate("Object.send(:remove_const, :String)")
    assert_equal false, evaluator.evaluate("Kernel.eval('1 + 1')")
  end

  test "handles parse errors gracefully" do
    assert_equal false, evaluator.evaluate("invalid ruby syntax {{")
    assert_equal false, evaluator.evaluate("def hack; end")
  end

  test "logs warnings for failed evaluations" do
    # Since Rails is defined in test environment, it will use Rails.logger
    # We need to capture the Rails logger output
    if defined?(Rails) && Rails.respond_to?(:logger)
      original_logger = Rails.logger
      log_output = StringIO.new
      Rails.logger = Logger.new(log_output)

      evaluator.evaluate("invalid syntax {{")

      Rails.logger = original_logger
      assert_match(/Condition evaluation failed/, log_output.string)
    else
      # For non-Rails environment, capture stderr
      original_stderr = $stderr
      $stderr = StringIO.new

      evaluator.evaluate("invalid syntax {{")

      assert_match(/Condition evaluation failed/, $stderr.string)
      $stderr = original_stderr
    end
  end

  test "handles nil ENV variables in comparisons" do
    ENV.delete("NON_EXISTENT") # Ensure it doesn't exist

    refute evaluator.evaluate("ENV['NON_EXISTENT'] == 'value'")
    assert evaluator.evaluate("ENV['NON_EXISTENT'] != 'value'")
  end
end
