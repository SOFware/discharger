# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.4.2] - Unreleased

## [0.4.1] - 2026-09-29

### Added

- Setup prints each step's elapsed time and the total (063521c)
- bin/setup opens with a do-not-edit notice, and `discharger:install --setup-only` regenerates only the script (71ee122)

### Changed

- Gem author listed as Savannah Albanez (a48c8d8)

### Removed

- Stale Qualify setup script from the repo root, never shipped in the gem (8744c43)

### Fixed

- Releases finish when the Slack token is missing or the post fails (3cf9b6d)
- bin/setup bootstraps a fresh clone: GitHub Packages credentials, bundle install, then re-exec under bundle exec (7196fe4)
- github_packages stores bundler credentials only after the source accepts them (41fab0f)
