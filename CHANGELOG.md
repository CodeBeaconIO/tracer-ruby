# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.3.0] - 2024-12-30

### Added
- Enhanced metadata
- Ability to disable trace from config file
- Ability to skip tracing via vscode filters

### Fixed
- script tracing path mismatch was preventing any methods from getting traced

### Changed
- Renamed bin/analyze to codebeacon and added to gemspec executables

## [0.1.0] - 2024-01-12

### Added
- Initial release of the RuntimeAnalysis gem
- Core functionality for tracing method calls and execution times
- Support for analyzing application, gem, and Ruby standard library code
- Database persistence for analysis results
- Basic configuration options
