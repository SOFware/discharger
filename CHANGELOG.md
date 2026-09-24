# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.4.0] - 2026-09-24

### Added

- pr_label option opening the finalize and version-bump PRs via gh with that label (08e1d10)

### Changed

- Auto-deploy releases tag the newest commit that changed the version's changelog section instead of requiring it at HEAD, and no longer open a production PR (476fe1b)
- Auto-deploy releases merge the release tag into the production branch (a7a1b49)

### Fixed

- retain_changelogs reaches Reissue, so finalize writes the archived changelog file (2a90edf)
- release:prepare branches from origin, so a stale local branch no longer yields an empty changelog (8eb5fd3)

## [0.3.5] - 2026-08-10

### Added

- github_packages setup step storing bundler credentials for a private GitHub Packages gem source via the gh CLI (2cff4b6)
