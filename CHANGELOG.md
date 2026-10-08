# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.5.4] - Unreleased

## [0.5.3] - 2026-10-08

### Added

- DISCHARGER_RELEASE_CONFIRM=1 skips the release confirmation prompt (4ff1cc8)

### Fixed

- release tasks abort with instructions instead of crashing when stdin is closed (4ff1cc8)
- release:prepare removes its finish branch when you stop at the confirm prompt (64ba2f5)
