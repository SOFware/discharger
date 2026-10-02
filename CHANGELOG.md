# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.5.0] - Unreleased

## [0.4.2] - 2026-09-30

### Added

- database.db_name in setup.yml sets the exported DB_NAME, or false leaves it to database.yml (836e811)

### Fixed

- The generated bin/setup stores a gh token only after the GitHub Packages source accepts it (1ef5a44)
