# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/)
and this project adheres to [Semantic Versioning](http://semver.org/).

## [0.3.3] - Unreleased

## [0.3.2] - 2026-07-15

### Changed

- Treat generated pg_tools setup as opt-in for apps that use structure.sql or PostgreSQL CLI workflows.

### Fixed

- Retry `brew bundle` once before failing setup, so transient Homebrew lock contention (e.g. two `bin/setup` runs on the same host) doesn't hard-fail the whole run.
- pg-tools wrappers no longer forward localhost -h/-p flags into docker exec, where the host-mapped port doesn't exist; remote hosts still pass through untouched (a3869d2)
