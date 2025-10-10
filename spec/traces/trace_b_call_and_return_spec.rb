require 'spec_helper'

RSpec.describe Codebeacon::Tracer do
  let(:library_file_contents) { nil }
  let(:file_contents) { <<-RUBY }
    class CLASS_NAME
      def hello_world
        yield if block_given?
      end
    end
  RUBY

  before do
    Codebeacon::Tracer.config.setup
    Codebeacon::Tracer::NodeSource.new('app', Codebeacon::Tracer.config.root_path)
    @trace_file = TraceFile.load!(file_contents)
    if library_file_contents
      @library_file = LibraryFile.load!(library_file_contents, class_name: library_class)
      Codebeacon::Tracer.config.exclude_paths << File.absolute_path(LibraryFile.dir)
    end
    Codebeacon::Tracer.config.dry_run = true
    Codebeacon::Tracer.config.local_methods_only = true
    Codebeacon::Tracer.config.local_lines_only = true
    @tracer = Codebeacon::Tracer::Tracer.new
    @trace_b_call = @tracer.trace_b_call
    @trace_b_return = @tracer.trace_b_return
  end

  after do
    @trace_file.cleanup
    @library_file&.cleanup
  end

  describe 'b_call and b_return tracing together' do
    context 'when block has method_id (internal block)' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_block
            [1, 2, 3].each { |x| x * 2 }
          end
        end
      RUBY

      it 'creates a node for an "each" block' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.method_with_block
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child.method).to eq(:method_with_block)
        expect(block_child.block).to be(true)
        expect(block_child.caller).to eq("each")
      end
    end

    context 'when multiple blocks are passed to different library methods' do
      let(:library_class) { "DualMethodLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class DualMethodLibrary
          def self.execute_first(&block)
            yield if block_given?
          end

          def self.execute_second(&block)
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_two_blocks
            first_block = proc { "first block" }
            second_block = proc { "second block" }
            DualMethodLibrary.execute_first(&first_block)
            DualMethodLibrary.execute_second(&second_block)
          end
        end
      RUBY

      it 'traces both blocks with correct caller attribution', :aggregate_failures do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.method_with_two_blocks
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root
        root.simple_print(show: [:caller, :method, :line])

        expect(root.children.length).to eq(2)

        first_block = root.children[0]
        expect(first_block).not_to be_nil
        expect(first_block.file).to eq(File.absolute_path(@trace_file.file_path))
        expect(first_block.line).to eq(3)  # Line where first_block is defined
        expect(first_block.method).to eq(:method_with_two_blocks)
        expect(first_block.depth).to eq(1)
        expect(first_block.caller).to eq("execute_first")
        expect(first_block.gem_entry).to eq(false)
        expect(first_block.parent).to eq(root)
        expect(first_block.block).to be(true)
        expect(first_block.node_source.name).to eq("app")

        second_block = root.children[1]
        expect(second_block).not_to be_nil
        expect(second_block.file).to eq(File.absolute_path(@trace_file.file_path))
        expect(second_block.line).to eq(4)  # Line where second_block is defined
        expect(second_block.method).to eq(:method_with_two_blocks)
        expect(second_block.depth).to eq(1)
        expect(second_block.caller).to eq("execute_second")
        expect(second_block.gem_entry).to eq(false)
        expect(second_block.parent).to eq(root)
        expect(second_block.block).to be(true)
        expect(second_block.node_source.name).to eq("app")
      end
    end

    context 'when library method accepts two procs as parameters' do
      let(:library_class) { "DualProcLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class DualProcLibrary
          def self.execute_both(first_proc, second_proc)
            first_proc.call
            second_proc.call
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_two_proc_params
            first_proc = proc { "first proc param" }
            second_proc = proc { "second proc param" }
            DualProcLibrary.execute_both(first_proc, second_proc)
          end
        end
      RUBY

      it 'traces both proc calls with correct caller attribution', :aggregate_failures do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.method_with_two_proc_params
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root
        root.simple_print(show: [:caller, :method, :line])

        expect(root.children.length).to eq(2)

        first_proc = root.children[0]
        expect(first_proc).not_to be_nil
        expect(first_proc.file).to eq(File.absolute_path(@trace_file.file_path))
        expect(first_proc.line).to eq(3)  # Line where first_proc is defined
        expect(first_proc.method).to eq(:method_with_two_proc_params)
        expect(first_proc.depth).to eq(1)
        expect(first_proc.caller).to eq("execute_both")  # Called from within library method
        expect(first_proc.gem_entry).to eq(false)
        expect(first_proc.parent).to eq(root)
        expect(first_proc.block).to be(true)
        expect(first_proc.node_source.name).to eq("app")

        second_proc = root.children[1]
        expect(second_proc).not_to be_nil
        expect(second_proc.file).to eq(File.absolute_path(@trace_file.file_path))
        expect(second_proc.line).to eq(4)  # Line where second_proc is defined
        expect(second_proc.method).to eq(:method_with_two_proc_params)
        expect(second_proc.depth).to eq(1)
        expect(second_proc.caller).to eq("execute_both")  # Same caller for both
        expect(second_proc.gem_entry).to eq(false)
        expect(second_proc.parent).to eq(root)
        expect(second_proc.block).to be(true)
        expect(second_proc.node_source.name).to eq("app")
      end
    end

    context 'when block is defined and called directly with .call' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_direct_call
            my_block = proc { "directly called" }
            my_block.call
          end
        end
      RUBY

      it 'traces the block call with all attributes', :aggregate_failures do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.method_with_direct_call
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child).not_to be_nil
        expect(block_child.file).to eq(File.absolute_path(@trace_file.file_path))
        expect(block_child.line).to eq(3)  # Line where my_block proc is defined
        expect(block_child.method).to eq(:method_with_direct_call)
        expect(block_child.depth).to eq(1)
        expect(block_child.caller).to eq("method_with_direct_call")  # Enclosing method when .call is in same method
        expect(block_child.gem_entry).to eq(false)
        expect(block_child.parent).to eq(root)
        expect(block_child.block).to be(true)
        expect(block_child.node_source.name).to eq("app")
      end
    end

    context 'when block is passed through mixed library and app methods' do
      let(:library_class) { "MixedLibraryYielder" }
      let(:library_file_contents) { <<-RUBY }
        class MixedLibraryYielder
          def self.library_call(&block)
            block.call if block
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def app_wrapper
            MixedLibraryYielder.library_call { app_inner_yield { "nested blocks" } }
          end

          def app_inner_yield
            yield if block_given?
          end
        end
      RUBY

      it 'correctly identifies callers for both library and app yielded blocks' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.app_wrapper
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        # Should have nested blocks:
        # 1. Outer block passed to library_call (yielded by library)
        #    - Contains inner block passed to app_inner_yield (yielded by app code)

        outer_block = root.children.first
        expect(outer_block).not_to be_nil
        expect(outer_block.method).to eq(:app_wrapper)
        expect(outer_block.block).to be(true)
        expect(outer_block.caller).to eq("library_call")

        # Inner block should be a child of the outer block
        expect(outer_block.children.length).to eq(1)
        inner_block = outer_block.children.first

        expect(inner_block).not_to be_nil
        expect(inner_block.method).to eq(:app_wrapper)  # Defined in app_wrapper, not app_inner_yield
        expect(inner_block.block).to be(true)
        expect(inner_block.caller).to eq("app_inner_yield")
      end
    end

    context 'when block is called multiple times' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def yielder
            3.times { yield }
          end

          def app_method
            yielder { "called multiple times" }
          end
        end
      RUBY

      it 'consistently identifies the same caller for all block calls' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.app_method
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        # The structure is nested because of how times { yield } works:
        # - times block (caller: "times")
        #   - app_method block (caller: "block in yielder")
        #     - times block (caller: "times")
        #       - app_method block (caller: "block in yielder")
        #         - times block (caller: "times")
        #           - app_method block (caller: "block in yielder")

        # Collect all app_method blocks by traversing the tree
        app_method_blocks = []

        def collect_blocks(node, method_name, collector)
          if node.block && node.method == method_name
            collector << node
          end
          node.children.each { |child| collect_blocks(child, method_name, collector) }
        end

        collect_blocks(root, :app_method, app_method_blocks)

        # Should have 3 app_method block calls (one for each yield iteration)
        expect(app_method_blocks.length).to eq(3)

        # All blocks should have the same caller (the block in yielder's times loop)
        app_method_blocks.each do |block_node|
          expect(block_node.caller).to eq("block in yielder")
        end
      end
    end

    context 'when using recursive block calls' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def recursive_yielder(n, &block)
            return if n <= 0
            yield
            recursive_yielder(n - 1, &block)
          end

          def app_method
            recursive_yielder(3) { "recursive block" }
          end
        end
      RUBY

      it 'tracks each recursion level separately with correct caller' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.app_method
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        # Collect all app_method blocks
        app_method_blocks = []

        def collect_blocks(node, method_name, collector)
          if node.block && node.method == method_name
            collector << node
          end
          node.children.each { |child| collect_blocks(child, method_name, collector) }
        end

        collect_blocks(root, :app_method, app_method_blocks)

        # Should have 3 block calls (one per recursion level)
        expect(app_method_blocks.length).to eq(3)

        # All blocks should have caller: "recursive_yielder"
        app_method_blocks.each do |block_node|
          expect(block_node.caller).to eq("recursive_yielder")
        end
      end
    end

    context 'when block calls another block' do
      let(:library_class) { "BlockCallerLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class BlockCallerLibrary
          def self.execute(&block)
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_nested_block_calls
            inner_block = proc { "inner" }
            outer_block = proc { inner_block.call }

            BlockCallerLibrary.execute(&outer_block)
          end
        end
      RUBY

      it 'traces both blocks with correct callers' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.method_with_nested_block_calls
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        # Outer block called by library
        outer_block = root.children.first
        expect(outer_block).not_to be_nil
        expect(outer_block.method).to eq(:method_with_nested_block_calls)
        expect(outer_block.block).to be(true)
        expect(outer_block.caller).to eq("execute")

        # Inner block called by outer block
        inner_block = outer_block.children.first
        expect(inner_block).not_to be_nil
        expect(inner_block.method).to eq(:method_with_nested_block_calls)
        expect(inner_block.block).to be(true)
        expect(inner_block.caller).to eq("block in method_with_nested_block_calls")
      end
    end

    context 'when C extension calls Ruby callback' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_c_callback
            [3, 1, 2].sort { |a, b| a <=> b }
          end
        end
      RUBY

      it 'traces block with C method as caller' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
        @trace_b_return.enable
          obj.method_with_c_callback
        @trace_b_call.disable
        @trace_b_return.disable

        root = @tracer.call_tree.root

        # The sort blocks should be siblings, not nested
        expect(root.children.length).to eq(3)

        root.children.each do |block_child|
          expect(block_child.method).to eq(:method_with_c_callback)
          expect(block_child.block).to be(true)
          expect(block_child.caller).to eq("sort")
        end
      end
    end

    context 'when not in debug mode' do
      around do |example|
        original_debug = Codebeacon::Tracer.config.debug?
        Codebeacon::Tracer.config.debug = false
        example.run
        Codebeacon::Tracer.config.debug = original_debug
      end

      context 'when an error is raised in the TracePoint while processing the block call' do
        it 'increments depth on call, creates node, then decrements depth on return', :aggregate_failures do
          initial_depth = @tracer.call_tree.depth
          root = @tracer.call_tree.root
          obj = @trace_file.klass.new

          @trace_b_call.enable
          @trace_b_return.enable
            obj.hello_world do
              'Hello, block!'
            end
          @trace_b_call.disable
          @trace_b_return.disable
          calling_line = __LINE__ - 5
          calling_file = __FILE__

          # Node should be created correctly
          node = root.children.first
          expect(node.file).to eq(File.absolute_path(calling_file))
          expect(node.line).to eq(calling_line)
          expect(node.method).to eq(nil)
          expect(node.depth).to eq(1)
          expect(node.caller).to eq("hello_world")
          expect(node.gem_entry).to eq(false)
          expect(node.parent).to eq(root)
          expect(node.block).to eq(true)
          expect(node.node_source.name).to eq("app")

          # With b_return enabled, stack should be unwound back to initial state
          expect(@tracer.call_tree.depth).to eq(initial_depth)
          expect(@tracer.call_tree.current_node).to be(root)
        end
      end

      context 'when exception is raised in block' do
        let(:library_class) { "ExceptionLibrary" }
        let(:library_file_contents) { <<-RUBY }
          class ExceptionLibrary
            def self.execute(&block)
              yield if block_given?
            end
          end
        RUBY

        let(:file_contents) { <<-RUBY }
          class CLASS_NAME
            def method_with_exception
              ExceptionLibrary.execute { raise "block error" }
            end
          end
        RUBY

        it 'traces b_call before exception propagates and does not break application' do
          obj = @trace_file.klass.new

          @trace_b_call.enable
          @trace_b_return.enable
            expect {
              obj.method_with_exception
            }.to raise_error(RuntimeError, "block error")
          @trace_b_call.disable
          @trace_b_return.disable

          root = @tracer.call_tree.root

          # The method_with_exception block is nested under the expect block
          expect_block = root.children.first
          block_child = expect_block.children.first

          expect(block_child).not_to be_nil
          expect(block_child.method).to eq(:method_with_exception)
          expect(block_child.block).to be(true)
          expect(block_child.caller).to eq("execute")
        end
      end
    end
  end
end
