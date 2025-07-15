require "test_helper"
require "tempfile"
require "fileutils"

module SetupRunnerTestHelper
  def setup
    @original_pwd = Dir.pwd
    @test_dir = Dir.mktmpdir("discharger_test")
    FileUtils.cd(@test_dir)
    # Disable spinners and colored output in tests
    ENV['NO_SPINNER'] = '1'
  end

  def teardown
    FileUtils.cd(@original_pwd)
    FileUtils.rm_rf(@test_dir)
  end

  def create_test_config(content = nil)
    content ||= default_test_config
    File.write("setup.yml", content)
  end

  def default_test_config
    <<~YAML
      app_name: TestApp
      commands:
        brew:
          enabled: true
        bundler:
          enabled: true
    YAML
  end

  def capture_output(&block)
    original_stdout = $stdout
    original_stderr = $stderr
    stdout_io = StringIO.new
    stderr_io = StringIO.new
    $stdout = stdout_io
    $stderr = stderr_io
    
    yield
    
    [stdout_io.string, stderr_io.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end

  def create_file(path, content = "")
    FileUtils.mkdir_p(File.dirname(path))
    File.write(path, content)
  end

  def assert_file_exists(path, message = nil)
    assert File.exist?(path), message || "Expected file #{path} to exist"
  end

  def assert_file_contains(path, content, message = nil)
    assert_file_exists(path)
    file_content = File.read(path)
    assert file_content.include?(content), 
           message || "Expected file #{path} to contain: #{content}\nActual content: #{file_content}"
  end
  
  def refute_file_exists(path, message = nil)
    refute File.exist?(path), message || "Expected file #{path} not to exist"
  end
  
  def refute_file_contains(path, content, message = nil)
    return unless File.exist?(path)
    file_content = File.read(path)
    refute file_content.include?(content), 
           message || "Expected file #{path} not to contain: #{content}\nActual content: #{file_content}"
  end

  def stub_system_call(command, success: true, output: "")
    # This is a simple stub - in real tests we'd use a mocking library
    # For now, we'll override the system method in the test
    define_singleton_method(:system) do |*args|
      if args.join(" ").include?(command)
        $?.success? ? success : !success
      else
        super(*args)
      end
    end
  end
end