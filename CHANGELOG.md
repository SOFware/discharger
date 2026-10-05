# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.5.2] - 2026-10-05

### Added

- github_packages.gh_timeout in setup.yml sets the gh deadline (e7d7620)
- pre_steps print elapsed time (9bdb05f)

### Changed

- github_packages step only checks the gh token; bin/setup stores credentials (e7d7620)

### Removed

- the unreachable seed_env option (8b7c654)

### Fixed

- gh calls in setup time out after 15s instead of hanging (e7d7620)

## [0.5.1] - 2026-10-02
