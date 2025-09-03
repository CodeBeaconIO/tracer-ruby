# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe "Boundary Caller Tracking Integration" do
  before(:each) do
    @db = SQLite3::Database.new(":memory:")
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::BoundaryCallerMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
    Codebeacon::Tracer::NodeBuilder.clear_caches
    Codebeacon::Tracer.config.dry_run = true

    # Setup configuration to load exclude paths
    Codebeacon::Tracer.config.setup

    # Create a temporary directory for "library" code
    @lib_dir = Dir.mktmpdir("test_library")

    # Add to exclude paths to simulate library code
    Codebeacon::Tracer.config.exclude_paths << @lib_dir
  end

  after(:each) do
    # Clean up temp directory
    FileUtils.rm_rf(@lib_dir) if @lib_dir && Dir.exist?(@lib_dir)

    # Remove from exclude paths
    Codebeacon::Tracer.config.exclude_paths.delete(@lib_dir) if @lib_dir
  end

  # Helper to create a "library" file that will be excluded from tracing
  def create_library_file(name, code)
    path = File.join(@lib_dir, "#{name}.rb")
    File.write(path, code)
    load path
    path
  end

  describe "Real library callback detection" do
    it "detects callbacks from simulated library iterator" do
      # Create a "library" file with an iterator method
      lib_path = create_library_file("test_iterator", <<~RUBY)
        module TestLibrary
          def self.each_item(items, &block)
            items.each { |item| block.call(item) }
          end
        end
      RUBY

      # Create test class with methods that will be traced
      test_class = Class.new do
        def process_items
          items = [1, 2, 3]
          TestLibrary.each_item(items) do |item|
            process_single_item(item)
          end
        end

        def process_single_item(item)
          item * 2
        end
      end

      # Trace the execution
      tracer = Codebeacon::Tracer::Tracer.new(name: "test_library_iterator")
      call_tree = nil

      tracer.enable_traces do
        instance = test_class.new
        instance.process_items
        call_tree = tracer.call_tree
      end

      # Find the process_single_item nodes (called from library)
      callback_nodes = []
      visit_nodes = ->(node) do
        if node.method == :process_single_item && node.callback_info
          callback_nodes << node
        end
        node.children.each { |child| visit_nodes.call(child) }
      end
      visit_nodes.call(call_tree.root)

      # Verify callbacks were detected
      expect(callback_nodes.length).to be > 0
      callback_nodes.each do |node|
        expect(node.callback_info).not_to be_nil
        expect(node.callback_info[:outgoing_method]).to eq("each_item")
      end
    end

    it "detects callbacks with different library method names" do
      # Create library with multiple iterator methods
      create_library_file("multi_iterator", <<~RUBY)
        module MultiIterator
          def self.transform(items, &block)
            items.map { |item| block.call(item) }
          end

          def self.filter(items, &block)
            items.select { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def use_transform
          MultiIterator.transform([1, 2, 3]) do |item|
            double_value(item)
          end
        end

        def use_filter
          MultiIterator.filter([1, 2, 3, 4]) do |item|
            is_even?(item)
          end
        end

        def double_value(item)
          item * 2
        end

        def is_even?(item)
          item.even?
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_multi_methods")
      call_tree = nil

      tracer.enable_traces do
        instance = test_class.new
        instance.use_transform
        instance.use_filter
        call_tree = tracer.call_tree
      end

      # Find callback nodes
      transform_callbacks = []
      filter_callbacks = []
      visit_nodes = ->(node) do
        if node.method == :double_value && node.callback_info
          transform_callbacks << node
        elsif node.method == :is_even? && node.callback_info
          filter_callbacks << node
        end
        node.children.each { |child| visit_nodes.call(child) }
      end
      visit_nodes.call(call_tree.root)

      # Verify transform callbacks
      expect(transform_callbacks.length).to be > 0
      transform_callbacks.each do |node|
        expect(node.callback_info[:outgoing_method]).to eq("transform")
      end

      # Verify filter callbacks
      expect(filter_callbacks.length).to be > 0
      filter_callbacks.each do |node|
        expect(node.callback_info[:outgoing_method]).to eq("filter")
      end
    end
  end

  describe "Nested callbacks" do
    it "handles App → Library → App callback with library_depth tracking" do
      create_library_file("nested_iterator", <<~RUBY)
        module NestedIterator
          def self.outer_each(items, &block)
            items.each { |item| block.call(item) }
          end

          def self.inner_each(items, &block)
            items.each { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def outer_method
          NestedIterator.outer_each([1, 2]) do |outer_item|
            process_outer(outer_item)
          end
        end

        def process_outer(item)
          NestedIterator.inner_each([3, 4]) do |inner_item|
            process_inner(inner_item)
          end
        end

        def process_inner(item)
          item * 2
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_nested_callbacks")
      call_tree = nil

      tracer.enable_traces do
        instance = test_class.new
        instance.outer_method
        call_tree = tracer.call_tree
      end

      # Find callback nodes
      outer_callbacks = []
      inner_nodes = []

      visit_nodes = ->(node) do
        if node.method == :process_outer && node.callback_info
          outer_callbacks << node
        elsif node.method == :process_inner
          inner_nodes << node
        end
        node.children.each { |child| visit_nodes.call(child) }
      end
      visit_nodes.call(call_tree.root)

      # Verify outer callbacks are marked
      expect(outer_callbacks.length).to be > 0
      outer_callbacks.each do |node|
        expect(node.callback_info[:outgoing_method]).to eq("outer_each")
      end

      # Verify inner nodes exist (but are NOT marked as callbacks themselves,
      # per design: children of callbacks don't propagate callback_info)
      expect(inner_nodes.length).to be > 0
      inner_nodes.each do |node|
        expect(node.callback_info).to be_nil
      end
    end

    it "does not mark child calls inside callbacks as callbacks themselves" do
      create_library_file("propagation_iterator", <<~RUBY)
        module PropagationIterator
          def self.each_item(items, &block)
            items.each { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def process_items
          PropagationIterator.each_item([1, 2]) do |item|
            process_with_helper(item)
          end
        end

        def process_with_helper(item)
          helper_method(item)
        end

        def helper_method(item)
          item * 2
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_callback_propagation")
      call_tree = nil

      tracer.enable_traces do
        instance = test_class.new
        instance.process_items
        call_tree = tracer.call_tree
      end

      # Find nodes
      process_nodes = []
      helper_nodes = []

      visit_nodes = ->(node) do
        if node.method == :process_with_helper
          process_nodes << node
        elsif node.method == :helper_method
          helper_nodes << node
        end
        node.children.each { |child| visit_nodes.call(child) }
      end
      visit_nodes.call(call_tree.root)

      # process_with_helper should be marked as callback
      expect(process_nodes.length).to be > 0
      process_nodes.each do |node|
        expect(node.callback_info).not_to be_nil
        expect(node.callback_info[:outgoing_method]).to eq("each_item")
      end

      # helper_method should NOT be marked as callback (it's a child of callback)
      expect(helper_nodes.length).to be > 0
      helper_nodes.each do |node|
        expect(node.callback_info).to be_nil
      end
    end
  end

  describe "Error recovery" do
    it "handles exceptions raised while library_depth > 0" do
      create_library_file("error_iterator", <<~RUBY)
        module ErrorIterator
          def self.each_with_error(items, &block)
            items.each { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def process_with_error
          ErrorIterator.each_with_error([1, 2, 3]) do |item|
            raise "Test error" if item == 2
            process_item(item)
          end
        rescue => e
          # Swallow error for test
        end

        def process_item(item)
          item * 2
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_error_recovery")

      # This should not raise and tracer state should remain consistent
      expect {
        tracer.enable_traces do
          instance = test_class.new
          instance.process_with_error
        end
      }.not_to raise_error

      # Verify the root node's library_depth is back to 0
      root = tracer.call_tree.root
      expect(root.library_depth).to eq(0)
    end
  end

  describe "Thread safety" do
    it "maintains separate library_depth per thread" do
      create_library_file("thread_iterator", <<~RUBY)
        module ThreadIterator
          def self.process_items(items, &block)
            items.each { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def process_in_thread(thread_id)
          ThreadIterator.process_items([1, 2]) do |item|
            calculate(thread_id, item)
          end
        end

        def calculate(thread_id, item)
          thread_id * item
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_thread_safety")

      threads = []
      tracer.enable_traces do
        3.times do |i|
          threads << Thread.new do
            instance = test_class.new
            instance.process_in_thread(i)
          end
        end
        threads.each(&:join)
      end

      # Verify tracer remains functional
      expect(tracer.tree_manager).to respond_to(:current)

      # After completion, library_depth should be 0
      expect(tracer.call_tree.root.library_depth).to eq(0)
    end
  end

  describe "Database persistence" do
    it "persists callback_info to boundary_callers table" do
      create_library_file("db_iterator", <<~RUBY)
        module DbIterator
          def self.process_each(items, &block)
            items.each { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def process_items
          DbIterator.process_each([1, 2]) do |item|
            transform(item)
          end
        end

        def transform(item)
          item * 2
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_db_persistence")
      call_tree = nil

      tracer.enable_traces do
        instance = test_class.new
        instance.process_items
        call_tree = tracer.call_tree
      end

      # Save tree to database
      @persistence_manager.save_tree(call_tree.root)

      # Query boundary_callers table
      results = @db.execute("SELECT outgoing_method, outgoing_method_as_called FROM boundary_callers")

      # Should have callback records
      expect(results.length).to be > 0

      # Verify callback info was persisted
      callback_records = results.select { |r| r[0] == "process_each" }
      expect(callback_records.length).to be > 0
    end

    it "maintains foreign key relationships between treenodes and boundary_callers" do
      create_library_file("fk_iterator", <<~RUBY)
        module FkIterator
          def self.map_items(items, &block)
            items.map { |item| block.call(item) }
          end
        end
      RUBY

      test_class = Class.new do
        def use_map
          FkIterator.map_items([1, 2]) do |item|
            double_it(item)
          end
        end

        def double_it(item)
          item * 2
        end
      end

      tracer = Codebeacon::Tracer::Tracer.new(name: "test_fk_relationships")
      call_tree = nil

      tracer.enable_traces do
        instance = test_class.new
        instance.use_map
        call_tree = tracer.call_tree
      end

      # Save tree to database
      @persistence_manager.save_tree(call_tree.root)

      # Join treenodes and boundary_callers
      results = @db.execute(<<-SQL)
        SELECT tn.method, bc.outgoing_method
        FROM treenodes tn
        INNER JOIN boundary_callers bc ON tn.boundary_caller_id = bc.id
        WHERE tn.method = 'double_it'
      SQL

      expect(results.length).to be > 0
      results.each do |row|
        expect(row[0]).to eq("double_it")
        expect(row[1]).to eq("map_items")
      end
    end
  end
end
