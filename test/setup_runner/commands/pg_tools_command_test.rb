require "test_helper"
require "setup_runner_test_helper"
require "discharger/setup_runner/commands/pg_tools_command"
require "logger"
require "open3"
require "ostruct"

class PgToolsCommandTest < ActiveSupport::TestCase
  include SetupRunnerTestHelper

  def setup
    super
    @config = OpenStruct.new(database: OpenStruct.new(name: "db-testapp"))
    @logger = Logger.new(StringIO.new)
    @command = Discharger::SetupRunner::Commands::PgToolsCommand.new(@config, @test_dir, @logger)
  end

  test "description returns correct text" do
    assert_equal "Setting up PostgreSQL tools wrappers", @command.description
  end

  test "can_execute? returns true when database config has name" do
    assert @command.can_execute?
  end

  test "can_execute? returns false when database config is missing" do
    config = OpenStruct.new
    command = Discharger::SetupRunner::Commands::PgToolsCommand.new(config, @test_dir, @logger)
    refute command.can_execute?
  end

  test "can_execute? returns false when database name is blank" do
    config = OpenStruct.new(database: OpenStruct.new(name: ""))
    command = Discharger::SetupRunner::Commands::PgToolsCommand.new(config, @test_dir, @logger)
    refute command.can_execute?
  end

  test "execute creates bin/pg-tools directory" do
    capture_output { @command.execute }
    assert File.directory?(File.join(@test_dir, "bin", "pg-tools"))
  end

  test "execute creates executable pg_dump wrapper" do
    capture_output { @command.execute }
    wrapper = File.join(@test_dir, "bin", "pg-tools", "pg_dump")
    assert_file_exists wrapper
    assert File.executable?(wrapper)
  end

  test "execute creates executable psql wrapper" do
    capture_output { @command.execute }
    wrapper = File.join(@test_dir, "bin", "pg-tools", "psql")
    assert_file_exists wrapper
    assert File.executable?(wrapper)
  end

  test "pg_dump wrapper uses correct container name" do
    capture_output { @command.execute }
    assert_file_contains File.join(@test_dir, "bin", "pg-tools", "pg_dump"), 'CONTAINER="db-testapp"'
  end

  test "psql wrapper uses correct container name" do
    capture_output { @command.execute }
    assert_file_contains File.join(@test_dir, "bin", "pg-tools", "psql"), 'CONTAINER="db-testapp"'
  end

  test "pg_dump wrapper fallback strips script dir from PATH to avoid infinite loop" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "pg_dump"))
    assert_includes content, "SCRIPT_DIR="
    assert_includes content, 'CLEAN_PATH="${PATH//$SCRIPT_DIR:/}"'
    assert_includes content, 'exec "$FALLBACK"'
  end

  test "psql wrapper fallback strips script dir from PATH to avoid infinite loop" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "psql"))
    assert_includes content, "SCRIPT_DIR="
    assert_includes content, 'CLEAN_PATH="${PATH//$SCRIPT_DIR:/}"'
    assert_includes content, 'exec "$FALLBACK"'
  end

  test "pg_dump wrapper fallback shows error when no binary found" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "pg_dump"))
    assert_includes content, "Error: pg_dump not found"
    assert_includes content, "exit 1"
  end

  test "psql wrapper fallback shows error when no binary found" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "psql"))
    assert_includes content, "Error: psql not found"
    assert_includes content, "exit 1"
  end

  test "pg_dump wrapper defaults to -U postgres" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "pg_dump"))
    assert_includes content, 'ARGS=("-U" "postgres" "${ARGS[@]}")'
  end

  test "psql wrapper defaults to -U postgres" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "psql"))
    assert_includes content, 'ARGS=("-U" "postgres" "${ARGS[@]}")'
  end

  test "execute creates envrc when none exists" do
    capture_output { @command.execute }
    assert_file_contains File.join(@test_dir, ".envrc"), "PATH_add bin/pg-tools"
  end

  test "execute does not overwrite existing envrc" do
    existing_content = "export FOO=bar\n"
    create_file(".envrc", existing_content)
    capture_output { @command.execute }
    assert_equal existing_content, File.read(File.join(@test_dir, ".envrc"))
  end

  test "pg_dump wrapper does not fallback with bare exec that could self-recurse" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "pg_dump"))
    # Should NOT contain a bare "exec pg_dump" without the FALLBACK variable
    refute_match(/^exec pg_dump/, content)
  end

  test "psql wrapper does not fallback with bare exec that could self-recurse" do
    capture_output { @command.execute }
    content = File.read(File.join(@test_dir, "bin", "pg-tools", "psql"))
    # Should NOT contain a bare "exec psql" without the FALLBACK variable
    refute_match(/^exec psql/, content)
  end

  test "psql wrapper drops localhost host and port before docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("psql", "-h", "localhost", "-p", "5434", "-d", "postgres", "-c", "SELECT 1")
    assert_equal ["-U", "postgres", "-d", "postgres", "-c", "SELECT 1"], args
  end

  test "psql wrapper drops a bare port flag before docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("psql", "-p", "5434", "-d", "postgres")
    assert_equal ["-U", "postgres", "-d", "postgres"], args
  end

  test "psql wrapper passes a remote host and port through to docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("psql", "-h", "db.example.com", "-p", "6543", "-d", "postgres")
    assert_equal ["-U", "postgres", "-d", "postgres", "-h", "db.example.com", "-p", "6543"], args
  end

  test "pg_dump wrapper drops localhost host and port before docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("pg_dump", "-h", "127.0.0.1", "-p", "5434", "-d", "testapp_development")
    assert_equal ["-U", "postgres", "-d", "testapp_development"], args
  end

  test "pg_dump wrapper passes a remote host and port through to docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("pg_dump", "-h", "db.example.com", "-p", "6543", "-d", "testapp_development")
    assert_equal ["-U", "postgres", "-d", "testapp_development", "-h", "db.example.com", "-p", "6543"], args
  end

  test "psql wrapper drops attached localhost host and port flags" do
    capture_output { @command.execute }
    args = docker_exec_args("psql", "-hlocalhost", "-p5434", "-d", "postgres")
    assert_equal ["-U", "postgres", "-d", "postgres"], args
  end

  test "psql wrapper drops equals-form localhost host and port flags" do
    capture_output { @command.execute }
    args = docker_exec_args("psql", "--host=localhost", "--port=5434", "-d", "postgres")
    assert_equal ["-U", "postgres", "-d", "postgres"], args
  end

  test "psql wrapper passes equals-form remote host and port through to docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("psql", "--host=db.example.com", "--port=6543", "-d", "postgres")
    assert_equal ["-U", "postgres", "-d", "postgres", "-h", "db.example.com", "-p", "6543"], args
  end

  test "pg_dump wrapper drops attached localhost host and port flags" do
    capture_output { @command.execute }
    args = docker_exec_args("pg_dump", "-h127.0.0.1", "-p5434", "-d", "testapp_development")
    assert_equal ["-U", "postgres", "-d", "testapp_development"], args
  end

  test "pg_dump wrapper passes attached remote host and port through to docker exec" do
    capture_output { @command.execute }
    args = docker_exec_args("pg_dump", "-hdb.example.com", "-p6543", "-d", "testapp_development")
    assert_equal ["-U", "postgres", "-d", "testapp_development", "-h", "db.example.com", "-p", "6543"], args
  end

  test "psql wrapper fails with a clear error when a host flag is missing its value" do
    capture_output { @command.execute }
    _out, err, status = run_wrapper("psql", "-d", "postgres", "-h")
    refute status.success?
    assert_includes err, "-h requires an argument"
  end

  test "psql wrapper fails with a clear error when a port flag is missing its value" do
    capture_output { @command.execute }
    _out, err, status = run_wrapper("psql", "-d", "postgres", "--port")
    refute status.success?
    assert_includes err, "--port requires an argument"
  end

  private

  def run_wrapper(tool, *args)
    stub_dir = File.join(@test_dir, "docker-stub")
    FileUtils.mkdir_p(stub_dir)
    stub_path = File.join(stub_dir, "docker")
    File.write(stub_path, <<~BASH)
      #!/usr/bin/env bash
      if [[ "$1" == "ps" ]]; then
        echo "db-testapp"
        exit 0
      fi
      shift 4
      printf '%s\\n' "$@"
    BASH
    FileUtils.chmod(0o755, stub_path)

    wrapper = File.join(@test_dir, "bin", "pg-tools", tool)
    Open3.capture3(
      {"PATH" => "#{stub_dir}:#{ENV["PATH"]}"},
      wrapper, *args
    )
  end

  def docker_exec_args(tool, *args)
    out, err, status = run_wrapper(tool, *args)
    assert status.success?, "wrapper failed: #{err}"
    out.split("\n")
  end
end
