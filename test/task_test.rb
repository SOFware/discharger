require_relative "test_helper"
require "tmpdir"
require "fileutils"

class DischargerTaskTest < Minitest::Test
  def setup
    @task = Discharger::Task.new
    @tmpdir = Dir.mktmpdir
    @changelog_file = File.join(@tmpdir, "CHANGELOG.md")
    @fragments_dir = File.join(@tmpdir, "changelog", "unreleased")

    @task.changelog_file = @changelog_file
    @task.changelog_fragments_dir = @fragments_dir
    @task.changelog_fragments_enabled = true

    # Create a sample changelog
    FileUtils.mkdir_p(File.dirname(@changelog_file))
    File.write(@changelog_file, sample_changelog)
  end

  def teardown
    FileUtils.rm_rf(@tmpdir) if @tmpdir
  end

  private

  def sample_changelog
    <<~CHANGELOG
      # Changelog

      All notable changes to this project will be documented in this file.

      ## [1.0.1] - Unreleased

      ## [1.0.0] - 2023-01-01

      ### Added

      - Initial release
    CHANGELOG
  end

  def test_initialize
    assert_equal :release, @task.name
    assert_equal "develop", @task.working_branch
    assert_equal "stage", @task.staging_branch
    assert_equal "main", @task.production_branch
    assert_equal "Release the current version to stage", @task.description
  end

  def test_create
    task = Discharger::Task.create(:test_task) do
      self.version_file = "VERSION"
      self.version_limit = "1.0.0"
      self.version_redo_proc = -> { "1.0.1" }
      self.changelog_file = "CHANGELOG.md"
      self.updated_paths = ["lib/"]
      self.commit = "Initial commit"
      self.commit_finalize = "Finalize commit"
    end

    assert_equal :test_task, task.name
    assert_equal "VERSION", task.version_file
    assert_equal "1.0.0", task.version_limit
    assert_equal "1.0.1", task.version_redo_proc.call
    assert_equal "CHANGELOG.md", task.changelog_file
    assert_equal ["lib/"], task.updated_paths
    assert_equal "Initial commit", task.commit
    assert_equal "Finalize commit", task.commit_finalize
  end

  def test_syscall_success
    output = StringIO.new
    assert_output(/Hello, World!/) do
      result = @task.syscall(["echo", "Hello, World!"], output:)
      assert result
    end
  end

  def test_syscall_failure
    assert_raises(SystemExit) do
      capture_io do
        @task.syscall(["false"])
      end
    end
  end

  def test_sysecho
    assert_output("Hello, World!\n") do
      assert @task.sysecho("Hello, World!")
    end
  end

  def test_define
    @task.chat_token = "fake_token"
    @task.release_message_channel = "#general"
    @task.version_constant = "VERSION"
    @task.pull_request_url = "http://example.com"

    @task.define

    assert_equal [
      "release",
      "release:build",
      "release:config",
      "release:prepare",
      "release:slack",
      "release:stage"
    ], Rake::Task.tasks.map(&:name).grep(/^release/).sort
  end

  def test_changelog_fragments_disabled_by_default
    task = Discharger::Task.new
    refute task.changelog_fragments_enabled
    assert_equal "changelog/unreleased", task.changelog_fragments_dir
    assert_equal ["Added", "Changed", "Deprecated", "Removed", "Fixed", "Security"], task.changelog_sections
  end

  def test_process_changelog_fragments_when_disabled
    @task.changelog_fragments_enabled = false
    @task.process_changelog_fragments
    # Should not crash and should not modify changelog
    assert_equal sample_changelog, File.read(@changelog_file)
  end

  def test_process_changelog_fragments_with_no_fragments
    FileUtils.mkdir_p(@fragments_dir)
    @task.process_changelog_fragments
    # Should not modify changelog if no fragments exist
    assert_equal sample_changelog, File.read(@changelog_file)
  end

  def test_process_changelog_fragments_with_fragments
    FileUtils.mkdir_p(@fragments_dir)

    # Create some fragment files
    File.write(File.join(@fragments_dir, "Added.new-feature.md"), "Added new user authentication")
    File.write(File.join(@fragments_dir, "Fixed.bug-fix.md"), "- Fixed memory leak in parser")
    File.write(File.join(@fragments_dir, "Changed.api-change.md"), "- Updated API response format\n- Improved error handling")

    @task.process_changelog_fragments

    updated_changelog = File.read(@changelog_file)

    # Check that fragments were added to the unreleased section
    assert_includes updated_changelog, "### Added"
    assert_includes updated_changelog, "- Added new user authentication"
    assert_includes updated_changelog, "### Fixed"
    assert_includes updated_changelog, "- Fixed memory leak in parser"
    assert_includes updated_changelog, "### Changed"
    assert_includes updated_changelog, "- Updated API response format"
    assert_includes updated_changelog, "- Improved error handling"

    # Check that fragment files were deleted
    refute File.exist?(File.join(@fragments_dir, "Added.new-feature.md"))
    refute File.exist?(File.join(@fragments_dir, "Fixed.bug-fix.md"))
    refute File.exist?(File.join(@fragments_dir, "Changed.api-change.md"))
  end

  def test_process_changelog_fragments_ignores_invalid_sections
    FileUtils.mkdir_p(@fragments_dir)

    # Create fragments with valid and invalid sections
    File.write(File.join(@fragments_dir, "Added.valid-feature.md"), "Added valid feature")
    File.write(File.join(@fragments_dir, "InvalidSection.invalid-feature.md"), "Invalid section content")

    @task.process_changelog_fragments

    updated_changelog = File.read(@changelog_file)

    # Check that only valid section was processed
    assert_includes updated_changelog, "### Added"
    assert_includes updated_changelog, "- Added valid feature"
    refute_includes updated_changelog, "InvalidSection"
    refute_includes updated_changelog, "Invalid section content"

    # Check that invalid fragment file was not deleted
    refute File.exist?(File.join(@fragments_dir, "Added.valid-feature.md"))
    assert File.exist?(File.join(@fragments_dir, "InvalidSection.invalid-feature.md"))
  end

  def test_process_changelog_fragments_case_insensitive_sections
    FileUtils.mkdir_p(@fragments_dir)

    # Create fragments with different case variations
    File.write(File.join(@fragments_dir, "added.lowercase-feature.md"), "Added lowercase feature")
    File.write(File.join(@fragments_dir, "FIXED.uppercase-bug.md"), "Fixed uppercase bug")
    File.write(File.join(@fragments_dir, "Changed.mixedcase-change.md"), "Changed mixedcase item")

    @task.process_changelog_fragments

    updated_changelog = File.read(@changelog_file)

    # Check that all sections were processed with proper capitalization
    assert_includes updated_changelog, "### Added"
    assert_includes updated_changelog, "- Added lowercase feature"
    assert_includes updated_changelog, "### Fixed"
    assert_includes updated_changelog, "- Fixed uppercase bug"
    assert_includes updated_changelog, "### Changed"
    assert_includes updated_changelog, "- Changed mixedcase item"

    # Check that all fragment files were deleted
    refute File.exist?(File.join(@fragments_dir, "added.lowercase-feature.md"))
    refute File.exist?(File.join(@fragments_dir, "FIXED.uppercase-bug.md"))
    refute File.exist?(File.join(@fragments_dir, "Changed.mixedcase-change.md"))
  end

  def test_process_changelog_fragments_handles_empty_files
    FileUtils.mkdir_p(@fragments_dir)

    File.write(File.join(@fragments_dir, "Added.feature.md"), "Added feature")
    File.write(File.join(@fragments_dir, "Fixed.empty.md"), "")
    File.write(File.join(@fragments_dir, "Changed.whitespace.md"), "   \n  \n   ")

    @task.process_changelog_fragments

    updated_changelog = File.read(@changelog_file)

    # Only non-empty fragment should be processed
    assert_includes updated_changelog, "### Added"
    assert_includes updated_changelog, "- Added feature"
    refute_includes updated_changelog, "### Fixed"
    refute_includes updated_changelog, "### Changed"

    # All fragment files should be deleted (even empty ones)
    refute File.exist?(File.join(@fragments_dir, "Added.feature.md"))
    refute File.exist?(File.join(@fragments_dir, "Fixed.empty.md"))
    refute File.exist?(File.join(@fragments_dir, "Changed.whitespace.md"))
  end

  def test_process_changelog_fragments_preserves_existing_content
    # Create changelog with existing content in unreleased section
    changelog_with_content = <<~CHANGELOG
      # Changelog

      ## [1.0.1] - Unreleased

      ### Added

      - Existing feature

      ## [1.0.0] - 2023-01-01

      ### Added

      - Initial release
    CHANGELOG

    File.write(@changelog_file, changelog_with_content)
    FileUtils.mkdir_p(@fragments_dir)
    File.write(File.join(@fragments_dir, "Added.new-feature.md"), "New feature from fragment")

    @task.process_changelog_fragments

    updated_changelog = File.read(@changelog_file)

    # Should contain both existing and new content
    assert_includes updated_changelog, "- Existing feature"
    assert_includes updated_changelog, "- New feature from fragment"
  end
end
