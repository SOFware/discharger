# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.2.13] - 2025-08-18

### Added
- Added changelog fragment support via `fragment_directory` configuration
  - Allows maintaining individual changelog entries in separate files
  - Fragments are automatically combined during releases
  - Helps avoid merge conflicts in CHANGELOG.md

### Fixed
- Fixed README documentation to correctly describe rake tasks
  - Clarified that documented tasks are for apps using Discharger
  - Added proper documentation for gem development tasks
  - Added manual release instructions

### Changed
- Added convenience rake tasks for releasing the gem (`prepare:patch`, `prepare:minor`, `prepare:major`)
- Updated gem to use Reissue for version and changelog management
