# frozen_string_literal: true

require_relative "reissue/version"
require_relative "reissue/version_updater"
require_relative "reissue/changelog_updater"

# Reissue is a module that provides functionality for updating version numbers and changelogs.
module Reissue
  # Updates the version number and changelog.
  #
  # @param version_file [String] The path to the version file.
  # @param changelog_file [String] The path to the changelog file. Default: CHANGELOG.md
  # @param segment [String] The segment of the version number to update. Default: patch
  # @param date [String] The release date. Default: Unreleased
  # @param changes [Hash] The changes made in this release. Default: {}
  # @param version_limit [Integer] The number of versions to retain in the changes. Default: 2
  #
  # @return [String] The new version number.
  def self.call(
    version_file:,
    changelog_file: "CHANGELOG.md",
    retain_changelogs: false,
    segment: "patch",
    date: "Unreleased",
    changes: {},
    version_limit: 2,
    version_redo_proc: nil
  )
    version_updater = VersionUpdater.new(version_file, version_redo_proc:)
    new_version = version_updater.call(segment, version_file:)
    if changelog_file
      changelog_updater = ChangelogUpdater.new(changelog_file)
      changelog_updater.call(new_version, date:, changes:, changelog_file:, version_limit:, retain_changelogs:)
    end
    new_version
  end

  # Finalizes the changelog for an unreleased version to set the release date.
  #
  # @param date [String] The release date.
  # @param changelog_file [String] The path to the changelog file.
  #
  # @return [Array] The version number and release date.
  def self.finalize(date = Date.today, changelog_file: "CHANGELOG.md", retain_changelogs: false)
    changelog_updater = ChangelogUpdater.new(changelog_file)
    changelog = changelog_updater.finalize(date:, changelog_file:, retain_changelogs:)
    changelog["versions"].first.slice("version", "date").values
  end

  # Reformats the changelog file to ensure it is correctly formatted.
  #
  # @param file [String] The path to the changelog file.
  # @param version_limit [Integer] The number of versions to retain in the changelog. Default: 2
  # @param retain_changelogs [Boolean, String, Proc] Whether to retain the changelog files for the previous versions.
  def self.reformat(file, version_limit: 2, retain_changelogs: false)
    changelog_updater = ChangelogUpdater.new(file)
    changelog_updater.reformat(version_limit:, retain_changelogs:)
  end

  INITIAL_CHANGES = {
    "Added" => ["Initial release"]
  }

  def self.generate_changelog(location, changes: {})
    template = <<~EOF
      # Changelog

      All notable changes to this project will be documented in this file.

      The format is based on [Keep a Changelog](http://keepachangelog.com/)
      and this project adheres to [Semantic Versioning](http://semver.org/).

      ## Unreleased

      ## [0.1.0]
    EOF

    File.write(location, template)
    changelog_updater = ChangelogUpdater.new(location)
    changelog_updater.call(
      "0.1.0",
      date: "Unreleased",
      changes: changes.empty? ? INITIAL_CHANGES : changes,
      changelog_file: location,
      version_limit: 1,
      retain_changelogs: false
    )
  end
end
