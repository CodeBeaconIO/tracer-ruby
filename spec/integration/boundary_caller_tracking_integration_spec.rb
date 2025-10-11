# frozen_string_literal: true

require 'spec_helper'
require 'tempfile'

RSpec.describe "Boundary Caller Tracking Integration" do
  let(:library_code) { nil }
  let(:library_class) { nil }

  before(:each) do
    @db = SQLite3::Database.new(":memory:")
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::BoundaryCallerMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
    Codebeacon::Tracer::NodeBuilder.clear_caches
    Codebeacon::Tracer.config.dry_run = true

    # "setup" is called primarily to load default exclude paths
    Codebeacon::Tracer.config.setup
    Codebeacon::Tracer.config.exclude_paths << File.absolute_path(LibraryFile.dir)

    if library_code
      @library_file = LibraryFile.load!(library_code, class_name: library_class)
    end
  end

  after(:each) do
    # Clean up library file
    @library_file&.cleanup
  end

  def collect_callback_nodes(root)
    callback_nodes = []
    visit_nodes = ->(node) do
      callback_nodes << node if node.block && node.callback_info
      node.children.each { |child| visit_nodes.call(child) }
    end
    visit_nodes.call(root)
    callback_nodes
  end

  # Helper to execute code with tracing and return the call tree
  def trace_execution(name, &block)
    tracer = Codebeacon::Tracer::Tracer.new(name: name)
    call_tree = nil
    tracer.enable_traces do
      block.call
      call_tree = tracer.call_tree
    end
    call_tree
  end

  describe "Real library callback detection" do
    context "when library calls back to app code" do
      let(:library_class) { "TestLibrary" }
      let(:library_code) {
        <<~RUBY
          module TestLibrary
            def self.each_item(items, &block)
              items.each { |item| block.call(item) }
            end

            # Negative test: alias exists but is not used, so outgoing_method_as_called should be nil
            singleton_class.send(:alias_method, :iterate_items, :each_item)
          end
        RUBY
      }

      let(:test_class) {
        Class.new do
          def process_items
            items = [1]
            TestLibrary.each_item(items) do |item|
              process_single_item(item)
            end
          end

          def process_items_with_alias
            items = [1]
            TestLibrary.iterate_items(items) do |item|
              process_single_item(item)
            end
          end

          def process_single_item(item)
            item * 2
          end
        end
      }

      it "detects callbacks from simulated library iterator" do
        call_tree = trace_execution("test_library_iterator") do
          instance = test_class.new
          instance.process_items
        end

        callback_nodes = collect_callback_nodes(call_tree.root)

        expect(callback_nodes.length).to eq(1)
        callback_nodes.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.callback_info[:outgoing_method]).to eq("each_item")
          expect(node.callback_info[:outgoing_method_as_called]).to be_nil  # Not using alias
          expect(node.children.length).to eq(1)
          expect(node.children.first.method).to eq(:process_single_item)
          expect(node.children.first.callback_info).to be_nil
        end
      end

      it "tracks aliased method when alias is used" do
        call_tree = trace_execution("test_library_iterator_alias") do
          instance = test_class.new
          instance.process_items_with_alias
        end

        callback_nodes = collect_callback_nodes(call_tree.root)

        callback_nodes.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.callback_info[:outgoing_method]).to eq("each_item")  # Actual method
          expect(node.callback_info[:outgoing_method_as_called]).to eq("iterate_items")  # Called via alias
          expect(node.children.length).to eq(1)
          expect(node.children.first.method).to eq(:process_single_item)
          expect(node.children.first.callback_info).to be_nil
        end
      end
    end

    context "when using multiple library methods" do
      let(:library_class) { "MultiIterator" }
      let(:library_code) {
        <<~RUBY
          module MultiIterator
            def self.transform(items, &block)
              items.map { |item| block.call(item) }
            end

            def self.filter(items, &block)
              items.select { |item| block.call(item) }
            end
          end
        RUBY
      }

      let(:test_class) {
        Class.new do
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
      }

      it "assigns multiple callbacks to the correct nodes" do
        call_tree = trace_execution("test_multi_methods") do
          instance = test_class.new
          instance.use_transform
          instance.use_filter
        end

        callback_nodes = collect_callback_nodes(call_tree.root)

        # Separate callbacks by outgoing method
        transform_callbacks = callback_nodes.select { |n| n.callback_info[:outgoing_method] == "transform" }
        filter_callbacks = callback_nodes.select { |n| n.callback_info[:outgoing_method] == "filter" }

        # Verify transform callbacks
        expect(transform_callbacks.length).to eq(3)
        transform_callbacks.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.children.length).to eq(1)
          expect(node.children.first.method).to eq(:double_value)
        end

        # Verify filter callbacks
        expect(filter_callbacks.length).to eq(4)
        filter_callbacks.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.children.length).to eq(1)
          expect(node.children.first.method).to eq(:is_even?)
        end
      end
    end
  end

  describe "Nested callbacks" do
    context "when app code calls library multiple times" do
      let(:library_class) { "NestedIterator" }
      let(:library_code) {
        <<~RUBY
          module NestedIterator
            def self.outer_each(items, &block)
              items.each { |item| block.call(item) }
            end

            def self.inner_each(items, &block)
              items.each { |item| block.call(item) }
            end
          end
        RUBY
      }

      let(:test_class) {
        Class.new do
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
      }

      it "handles App → Library → App callback with library_depth tracking" do
        call_tree = trace_execution("test_nested_callbacks") do
          instance = test_class.new
          instance.outer_method
        end

        callback_nodes = collect_callback_nodes(call_tree.root)

        # Separate outer and inner callback blocks
        outer_callbacks = callback_nodes.select { |n| n.callback_info[:outgoing_method] == "outer_each" }
        inner_callbacks = callback_nodes.select { |n| n.callback_info[:outgoing_method] == "inner_each" }

        # Verify outer callbacks
        expect(outer_callbacks.length).to eq(2)
        outer_callbacks.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.children.length).to eq(1)
          expect(node.children.first.method).to eq(:process_outer)
        end

        # Verify inner callbacks (nested within process_outer)
        expect(inner_callbacks.length).to eq(4)  # 2 outer iterations × 2 inner iterations
        inner_callbacks.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.children.length).to eq(1)
          expect(node.children.first.method).to eq(:process_inner)
          # process_inner should NOT have callback_info (it's a child of callback)
          expect(node.children.first.callback_info).to be_nil
        end
      end
    end

    context "when callback has nested child calls" do
      let(:library_class) { "PropagationIterator" }
      let(:library_code) {
        <<~RUBY
          module PropagationIterator
            def self.each_item(items, &block)
              items.each { |item| block.call(item) }
            end
          end
        RUBY
      }

      let(:test_class) {
        Class.new do
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
      }

      it "does not mark child calls inside callbacks as callbacks themselves" do
        call_tree = trace_execution("test_callback_propagation") do
          instance = test_class.new
          instance.process_items
        end

        callback_nodes = collect_callback_nodes(call_tree.root)

        # Verify callback blocks
        expect(callback_nodes.length).to eq(2)
        callback_nodes.each do |node|
          expect(node.block).to be(true)
          expect(node.callback_info).not_to be_nil
          expect(node.callback_info[:outgoing_method]).to eq("each_item")

          # Verify the immediate child (process_with_helper) has no callback_info
          expect(node.children.length).to eq(1)
          process_node = node.children.first
          expect(process_node.method).to eq(:process_with_helper)
          expect(process_node.callback_info).to be_nil

          # Verify the nested child (helper_method) also has no callback_info
          expect(process_node.children.length).to eq(1)
          helper_node = process_node.children.first
          expect(helper_node.method).to eq(:helper_method)
          expect(helper_node.callback_info).to be_nil
        end
      end
    end
  end

  describe "Error recovery" do
    it "handles exceptions raised while library_depth > 0" do
      library_file = LibraryFile.load!(<<~RUBY, class_name: "ErrorIterator")
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

      library_file.cleanup
    end
  end

  describe "Thread safety" do
    it "maintains separate library_depth per thread" do
      library_file = LibraryFile.load!(<<~RUBY, class_name: "ThreadIterator")
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

      library_file.cleanup
    end
  end

  describe "Database persistence" do
    context "when saving callback info" do
      let(:library_class) { "DbIterator" }
      let(:library_code) {
        <<~RUBY
          module DbIterator
            def self.process_each(items, &block)
              items.each { |item| block.call(item) }
            end
          end
        RUBY
      }

      let(:test_class) {
        Class.new do
          def process_items
            DbIterator.process_each([1, 2]) do |item|
              transform(item)
            end
          end

          def transform(item)
            item * 2
          end
        end
      }

      it "persists callback_info to boundary_callers table" do
        call_tree = trace_execution("test_db_persistence") do
          instance = test_class.new
          instance.process_items
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
    end

    context "when verifying foreign key relationships" do
      let(:library_class) { "FkIterator" }
      let(:library_code) {
        <<~RUBY
          module FkIterator
            def self.map_items(items, &block)
              items.map { |item| block.call(item) }
            end
          end
        RUBY
      }

      let(:test_class) {
        Class.new do
          def use_map
            FkIterator.map_items([1, 2]) do |item|
              double_it(item)
            end
          end

          def double_it(item)
            item * 2
          end
        end
      }

      it "maintains foreign key relationships between treenodes and boundary_callers" do
        call_tree = trace_execution("test_fk_relationships") do
          instance = test_class.new
          instance.use_map
        end

        # Save tree to database
        @persistence_manager.save_tree(call_tree.root)

        # Join treenodes and boundary_callers
        # Blocks now have callback_info, not the methods called within them
        results = @db.execute(<<-SQL)
          SELECT tn.method, bc.outgoing_method
          FROM treenodes tn
          INNER JOIN boundary_callers bc ON tn.boundary_caller_id = bc.id
          WHERE tn.block = 1
        SQL

        expect(results.length).to be > 0
        # Verify the block has the correct callback info
        map_callbacks = results.select { |r| r[1] == "map_items" }
        expect(map_callbacks.length).to be > 0
      end
    end
  end
end
