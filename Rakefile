# frozen_string_literal: true

require "bundler/gem_tasks"
require "rspec/core/rake_task"
require "yard"
require "rubocop/rake_task"

RSpec::Core::RakeTask.new(:spec)

YARD::Rake::YardocTask.new do |t|
  t.files = ["lib/**/*.rb"]
  t.stats_options = ["--list-undoc"]
end

RuboCop::RakeTask.new

task default: %i[spec rubocop yard]
