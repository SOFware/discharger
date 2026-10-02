# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.5.0] - 2026-10-02

### Added

- discharger:setup:check fails when bin/setup is missing or differs from the installed gem's template, naming the regenerate command and the first differing line (512544a)

### Changed

- Setup creates missing config/**/*.example and .env.example counterparts before pre_steps and Rails, so apps no longer copy them in pre_steps (e7a8ce9)
- rake release refuses to reset the working branch over unpushed local commits (6d87ce7)
- rake release tags the release commit on the working branch and pushes the tag; nothing merges into a production branch (af4484d)
- working_branch defaults to main (af4484d)
- rake release checks the tree, unpushed commits, the release commit and the tag before asking to confirm (af4484d)
- rake release stops with a clear message when the version's tag already exists on origin (af4484d)

### Removed

- staging_branch, production_branch, auto_deploy_staging and description settings; their writers warn and do nothing until 0.6 (af4484d)
- release:stage, release:build and DISCHARGER_BUILD_BRANCH (af4484d)
- the runbook preview on the stage build (af4484d)

### Fixed

- bin/setup stores a gh token only when the GitHub Packages source answers 2xx (0ed1239)
- The yarn step installs the packageManager yarn with corepack install instead of corepack use, so setup no longer rewrites package.json (91967a1)

## [0.4.2] - 2026-09-30

### Added

- database.db_name in setup.yml sets the exported DB_NAME, or false leaves it to database.yml (836e811)

### Fixed

- The generated bin/setup stores a gh token only after the GitHub Packages source accepts it (1ef5a44)
