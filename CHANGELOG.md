# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.2.14] - 2025-09-23

### Added

- Documentation about setup features and custom commands.
- Reissue deprecated fragment_directory and added fragment.

### Removed

- Got rid of the prepare release yml and action, only the Release gem to RubyGems.org is needed now.
- Got rid of the code climate action.

### Fixed

- Updated release documentation.

## [0.2.13] - 2025-09-02

### Added

- Added clean up fragment_directory task on Task.
- Added trusted publisher flow to GitHub release action.
- Adding commit step if needed after the finalize.

### Fixed

- Fixed version on GitHub trusted publisher action.
- Added debugging for OIDC.
- Switching back to version 1.0.0 for trusted publisher
- Now going for the official RubyGems GitHub action for the gem publishing.
