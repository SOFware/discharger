# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

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

## [0.4.0] - 2026-09-24

### Added

- pr_label option opening the finalize and version-bump PRs via gh with that label (08e1d10)

### Changed

- Auto-deploy releases tag the newest commit that changed the version's changelog section instead of requiring it at HEAD, and no longer open a production PR (476fe1b)
- Auto-deploy releases merge the release tag into the production branch (a7a1b49)

### Fixed

- retain_changelogs reaches Reissue, so finalize writes the archived changelog file (2a90edf)
- release:prepare branches from origin, so a stale local branch no longer yields an empty changelog (8eb5fd3)
