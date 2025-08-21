# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Commands

### Testing
- `bundle exec rspec` - Run all tests
- `bundle exec rspec spec/path/to/specific_spec.rb` - Run a specific test file
- `bundle exec rspec spec/path/to/specific_spec.rb:line_number` - Run a specific test

### Code Quality
- `bundle exec rubocop` - Run RuboCop linter (must pass)
- `bundle exec rubocop --auto-correct` - Auto-fix RuboCop violations
- `bundle exec standardrb` - Run Standard Ruby formatter (if using Standard gem)

### Documentation
- `bundle exec yard` - Generate YARD documentation
- `bundle exec yard --list-undoc` - Show undocumented methods

### Development
- `bundle install` - Install dependencies
- `bin/console` - Interactive console for experimentation
- `bin/codebeacon path/to/script.rb` - Execute script with tracing (development)
- `codebeacon path/to/script.rb` - Execute script with tracing (installed gem)

### Gem Development
- `bundle exec rake install` - Install gem locally
- `gem build codebeacon-tracer.gemspec` - Build gem package
- `bundle exec rake release` - Release new version (creates git tag, pushes commits and gem)

### Default Rake Tasks
- `rake` or `bundle exec rake` - Runs default tasks: `spec`, `rubocop`, and `yard`

## Architecture Overview

### Core Purpose
Code Beacon Tracer is a Ruby gem for dynamic runtime analysis that traces method calls and creates call graphs. It persists execution data to SQLite databases for analysis by external visualization tools like the Code Beacon VSCode extension.

### Key Components

#### Main Tracer (`lib/codebeacon/tracer/src/tracer.rb`)
- Central orchestrator that manages Ruby's TracePoint API
- Handles method call/return events (`call`, `return`, `b_call`, `b_return`)
- Manages thread-local call trees and coordinates persistence
- Implements filtering and skip logic for performance

#### Data Persistence Layer (`lib/codebeacon/tracer/src/data/`)
- **Database**: SQLite schema management with timestamped files and symlinks
- **TreeNodeMapper**: Maps call tree nodes to database records
- **AsyncPersistenceManager**: Background persistence to avoid blocking execution
- **MetadataMapper**: Stores trace metadata (name, description, version)
- **NodeSourceMapper**: Maps source code locations and method signatures

#### Models (`lib/codebeacon/tracer/src/models/`)
- **CallTree**: Represents execution call hierarchies
- **TreeNode**: Individual method call nodes with timing and context
- **ThreadLocalCallTreeManager**: Manages separate call trees per thread
- **NodeBuilder**: Constructs nodes from TracePoint events

#### Rails Integration (`lib/codebeacon/tracer/src/rails/`)
- **Middleware**: Automatically traces all Rails requests
- **Railtie**: Rails framework integration and configuration

### Data Flow
1. Tracer starts and registers TracePoint callbacks
2. Method calls trigger callbacks that create TreeNode instances
3. Nodes are built into CallTree structures per thread
4. AsyncPersistenceManager batches and persists data to SQLite
5. External tools query the database for visualization

### Key Design Patterns
- **Thread Safety**: Each thread maintains its own call tree to avoid conflicts
- **Asynchronous Persistence**: Database writes happen in background to minimize performance impact
- **Filtering System**: Skip cache and exclusion patterns prevent tracing of uninteresting code
- **Timestamped Databases**: Each trace session creates a new database file with symlink for latest

## Configuration
- Configuration loaded from `lib/codebeacon/tracer/config.yml`
- Database storage managed automatically with cleanup of old files
- Rails integration activates automatically when Rails is detected

## Testing Guidelines
- Follow TDD: write failing test first, then implement
- Use RSpec with descriptive test names and AAA pattern (Arrange, Act, Assert)
- Prefer integration tests for complex interactions, unit tests for algorithms
- Test files mirror source structure in `spec/` directory
- Use `let` for test data setup, avoid instance variables
- Use proper RSpec matchers: `eq`, `be_truthy`, `be_falsy`, etc.

## Code Standards
- Use `frozen_string_literal: true` at top of all files
- Double quotes for string literals (per RuboCop config)
- Snake_case for methods/variables, CamelCase for classes/modules
- Method length under 20 lines, line length under 120 characters
- Use `require_relative` for internal dependencies, `require` for external gems
- Follow semantic versioning for releases
- Use Conventional Commits format for commit messages

## Development Workflow
1. All tests must pass: `bundle exec rspec`
2. All RuboCop checks must pass: `bundle exec rubocop` 
3. YARD documentation should generate without warnings
4. Use proper Ruby gem structure with namespacing under `Codebeacon::Tracer`
