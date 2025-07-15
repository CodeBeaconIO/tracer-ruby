# frozen_string_literal: true

require_relative "lib/codebeacon/tracer/version"

Gem::Specification.new do |spec|
  spec.name = "codebeacon-tracer"
  spec.version = Codebeacon::Tracer::VERSION
  spec.authors = ["Jonathan Conley"]
  spec.email = ["conley.jj@gmail.com"]

  spec.summary = "A Ruby gem for building code flows of your application during runtime."
  spec.description = "Codebeacon::Tracer provides tools to trace and capture call graphs of execution paths."
  spec.homepage = "https://github.com/jconley88/codebeacon-tracer"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 2.6.0"

  # Remove the TODO and set to RubyGems
  spec.metadata["allowed_push_host"] = "https://rubygems.org"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/jconley88/codebeacon-tracer"
  spec.metadata["changelog_uri"] = "https://github.com/jconley88/codebeacon-tracer/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://rubydoc.info/gems/codebeacon-tracer"

  # Specify which files should be added to the gem when it is released.
  spec.files = [
    "lib/codebeacon-tracer.rb",
    "lib/codebeacon/tracer/version.rb",
    *Dir.glob("lib/codebeacon/tracer/src/**/*.rb")
  ]
  spec.bindir = "bin"
  spec.executables = ["codebeacon"]
  spec.require_paths = ["lib"]

  # Dependencies
  spec.add_dependency "parser", "~> 3.2"
  spec.add_dependency 'sqlite3', '~> 1.4'
  spec.add_dependency "listen", "~> 3.8", ">= 3.8.0"
  spec.add_development_dependency "pry", "~> 0.14"
  spec.add_development_dependency "debug", "~> 1.8"
  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "yard", "~> 0.9"
  spec.add_development_dependency "rubocop", "~> 1.21"
  spec.add_development_dependency "rubocop-rake", "~> 0.6"
  spec.add_development_dependency "rubocop-rspec", "~> 2.22"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end 