# frozen_string_literal: true

require "codebeacon-tracer"
require "pry"
require "debug"
require_relative 'support/trace_file'
require_relative 'support/cannot_inspect'
require_relative 'support/cannot_to_s'

Codebeacon::Tracer.config.debug = true

RSpec.configure do |config|
  srand(config.seed)

  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = ".rspec_status"

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end
