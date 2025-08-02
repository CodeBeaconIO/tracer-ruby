#! /usr/bin/env ruby
# frozen_string_literal: true

require "benchmark"
require "fileutils"
require_relative "../lib/codebeacon-tracer"

# --- Helper Functions ---
def find_best_params(target_nodes)
  best_params = { depth: 0, branching: 0, nodes: 0, diff: Float::INFINITY }

  # Iterate through possible depths and branching factors to find the best fit
  (2..10).each do |depth|
    (2..20).each do |branching|
      num_method_calls = ((branching**(depth + 1) - 1) / (branching - 1.0)).round
      num_non_leaf_calls = ((branching**depth - 1) / (branching - 1.0)).round
      num_block_calls = num_non_leaf_calls * branching
      total_nodes = num_method_calls + num_block_calls
      diff = (target_nodes - total_nodes).abs

      if diff < best_params[:diff]
        best_params = { depth: depth, branching: branching, nodes: total_nodes, diff: diff }
      end
    end
  end
  best_params
end

# --- Configuration ---
if ARGV[0].nil?
  puts "Usage: #{$0} <target_nodes>"
  puts "Example: #{$0} 100000"
  puts
end

TARGET_NODES = ARGV[0]&.to_i || 100_000
params = find_best_params(TARGET_NODES)
RECURSION_DEPTH = params[:depth]
BRANCHING_FACTOR = params[:branching]
TOTAL_NODES = params[:nodes]

# --- Recursive method to generate a call tree ---
$method_call_counter = 0
$block_call_counter = 0
def generate_calls(depth, branching_factor)
  $method_call_counter += 1
  return if depth <= 0

  (1..branching_factor).each do |_i|
    $block_call_counter += 1
    generate_calls(depth - 1, branching_factor)
  end
end

# --- Benchmark Execution ---
puts "Starting performance benchmark..."
puts "Target nodes: #{TARGET_NODES}. Using depth=#{RECURSION_DEPTH}, branching=#{BRANCHING_FACTOR} to generate #{TOTAL_NODES} nodes."
puts "--------------------------------------------------\n"

# --- Phase 1: Baseline Generation (No Tracing) ---
puts "--- Phase 1: Baseline Call Generation (No Tracing) ---"
$method_call_counter = 0
$block_call_counter = 0
baseline_time = Benchmark.measure { generate_calls(RECURSION_DEPTH, BRANCHING_FACTOR) }
puts "Call generation complete. Total calls: #{$method_call_counter + $block_call_counter}"
puts "Baseline time: #{baseline_time.real.round(4)}s"
puts "--------------------------------------------------\n"


# --- Phase 2: Call Generation with Tracing ---
puts "--- Phase 2: Call Generation with Tracing Enabled ---"
Codebeacon::Tracer.config.instance_variable_set(:@trace_enabled, true)
Codebeacon::Tracer.config.instance_variable_set(:@dry_run, false)
Codebeacon::Tracer.send(:setup)
tracer = Codebeacon::Tracer::Tracer.new(name: "Benchmark", description: "Persistence Test")
Codebeacon::Tracer.instance_variable_set(:@tracer, tracer)

$method_call_counter = 0
$block_call_counter = 0
tracing_time = Benchmark.measure do
  tracer.enable_traces do
    generate_calls(RECURSION_DEPTH, BRANCHING_FACTOR)
  end
end
puts "Call generation complete."
puts "Total calls: #{$method_call_counter + $block_call_counter}"
puts "Tracing overhead time: #{tracing_time.real.round(4)}s"
puts "--------------------------------------------------\n"


# --- Phase 3: Persistence ---
puts "--- Phase 3: Persistence ---"
persistence_time = nil
begin
  persistence_time = Benchmark.measure { Codebeacon::Tracer.send(:persist, tracer.metadata) }
ensure
  puts "Time for persistence only: #{persistence_time.real.round(4)}s"
  puts "\n-------------------------\n"
  puts "Database has been created and populated for inspection."
  puts "Database path: #{Codebeacon::Tracer.config.db_path}"
  puts "Press Enter to continue with cleanup..."
  STDIN.gets
  Codebeacon::Tracer.send(:cleanup)
  db_path = Codebeacon::Tracer.config.db_path
  db_files = Dir.glob(File.join(db_path, "*.db*"))
  db_files.each { |file| File.delete(file) if File.exist?(file) }
  puts "\nCleaned up generated database files from #{db_path}"
end

puts "\n--- Final Benchmark Summary ---"
puts "Baseline Generation: #{baseline_time.real.round(4)}s"
puts "Tracing Overhead:    #{tracing_time.real.round(4)}s"
puts "Persistence:         #{persistence_time.real.round(4)}s"
puts "---------------------------------"
