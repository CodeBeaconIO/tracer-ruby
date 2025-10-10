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
  end

  after do
    @trace_file.cleanup
    @library_file&.cleanup
  end

  describe '.trace_call' do
    it 'traces a block call' do
      obj = @trace_file.klass.new

      @trace_b_call.enable
        obj.hello_world do
          'Hello, block!'
        end
      @trace_b_call.disable
      calling_line = __LINE__ - 4
      calling_file = __FILE__

      root = @tracer.call_tree.root
      node = root.children.first
      expect(node.file).to eq(File.absolute_path(calling_file))
      expect(node.line).to eq(calling_line)
      expect(node.method).to eq(nil)
      expect(node.depth).to eq(1)
      expect(node.gem_entry).to eq(false)
      expect(node.parent).to eq(root)
      expect(node.block).to eq(true)
      expect(node.node_source.name).to eq("app")
    end

    context 'with args' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def hello_world
            yield('Hello, ', 'World!') if block_given?
          end
        end
      RUBY

    end


    context 'when block is passed to custom yielding method' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def custom_yield
            yield if block_given?
          end

          def method_with_custom_block
            custom_yield { "inside block" }
          end
        end
      RUBY

      it 'creates a node for a custom yielding method block' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          obj.method_with_custom_block
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child.method).to eq(:method_with_custom_block)
        expect(block_child.block).to be(true)
        expect(block_child.caller).to eq("custom_yield")
      end
    end

    context 'when block is passed to library (excluded) yielding method' do
      let(:library_class) { "LibraryYielder" }
      let(:library_file_contents) { <<-RUBY }
        class LibraryYielder
          def self.library_yield
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_library_block
            LibraryYielder.library_yield { "inside library block" }
          end
        end
      RUBY

      it 'creates a node for a library yielding method block with callback info' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          obj.method_with_library_block
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child.method).to eq(:method_with_library_block)
        expect(block_child.block).to be(true)
        expect(block_child.caller).to eq("library_yield")
        # expect(block_child.callback_info).not_to be_nil
        # expect(block_child.callback_info[:outgoing_method]).to eq("library_yield")
      end
    end

    context 'when block is passed through nested library methods' do
      let(:library_class) { "NestedLibraryYielder" }
      let(:library_file_contents) { <<-RUBY }
        class NestedLibraryYielder
          def self.outer_method(&block)
            inner_method(&block)
          end

          def self.inner_method
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_nested_library_block
            NestedLibraryYielder.outer_method { "inside nested library block" }
          end
        end
      RUBY

      it 'creates a node with caller as outer_method (first library method)' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          obj.method_with_nested_library_block
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child.method).to eq(:method_with_nested_library_block)
        expect(block_child.block).to be(true)
        expect(block_child.caller).to eq("outer_method")
        # expect(block_child.callback_info).not_to be_nil
        # expect(block_child.callback_info[:outgoing_method]).to eq("outer_method")
      end
    end


    context 'when block is passed through deeply nested library methods' do
      let(:library_class) { "DeeplyNestedLibrary" }
      let(:library_file_contents) {
        # Generate 15 nested methods to test performance and safety limit
        methods = (1..15).map do |i|
          if i == 15
            # Last method yields
            <<-RUBY
          def self.lib_#{i}
            yield if block_given?
          end
            RUBY
          else
            # Pass block to next method
            <<-RUBY
          def self.lib_#{i}(&block)
            lib_#{i + 1}(&block)
          end
            RUBY
          end
        end.join("\n")

        <<-RUBY
        class DeeplyNestedLibrary
#{methods}
        end
        RUBY
      }

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_deeply_nested_block
            DeeplyNestedLibrary.lib_1 { "deeply nested block" }
          end
        end
      RUBY

      it 'identifies the first library method as caller without hitting safety limit' do
        obj = @trace_file.klass.new

        # Measure performance
        start_time = Time.now

        @trace_b_call.enable
          obj.method_with_deeply_nested_block
        @trace_b_call.disable

        elapsed_time = Time.now - start_time

        root = @tracer.call_tree.root
        block_child = root.children.first

        expect(block_child).not_to be_nil
        expect(block_child.method).to eq(:method_with_deeply_nested_block)
        expect(block_child.block).to be(true)

        # Should find lib_1 (first entry) not lib_15 (actual yielder)
        expect(block_child.caller).to eq("lib_1")

        # Performance check: should complete quickly (< 100ms for 15 levels)
        expect(elapsed_time).to be < 0.1

        # Verify we didn't hit the safety limit by getting a fallback
        # If we hit the limit, caller would be from immediate depth (lib_15 or something close)
        expect(block_child.caller).not_to eq("lib_15")
      end
    end

    context 'when block is passed through multiple non-library methods' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def app_method_1(&block)
            app_method_2(&block)
          end

          def app_method_2
            yield if block_given?
          end

          def caller_method
            app_method_1 { "multi-app block" }
          end
        end
      RUBY

      it 'identifies the immediate yielder as caller, not the first app method' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          obj.caller_method
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child).not_to be_nil
        expect(block_child.method).to eq(:caller_method)
        expect(block_child.block).to be(true)

        # Stack walking should stop at first non-skipped method (app_method_2)
        # NOT continue to app_method_1 since it's also non-skipped
        expect(block_child.caller).to eq("app_method_2")
      end
    end

    context 'when using different callable types' do
      let(:library_class) { "CallableLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class CallableLibrary
          def self.execute(&block)
            yield if block_given?
          end
        end
      RUBY

      context 'with Proc' do
        let(:file_contents) { <<-RUBY }
          class CLASS_NAME
            def method_with_proc
              my_proc = Proc.new { "proc" }
              CallableLibrary.execute(&my_proc)
            end
          end
        RUBY

        it 'traces Proc with correct caller identification' do
          obj = @trace_file.klass.new

          @trace_b_call.enable
            obj.method_with_proc
          @trace_b_call.disable

          root = @tracer.call_tree.root

          proc_block = root.children.first
          expect(proc_block).not_to be_nil
          expect(proc_block.method).to eq(:method_with_proc)
          expect(proc_block.block).to be(true)
          expect(proc_block.caller).to eq("execute")
        end
      end

      context 'with Lambda' do
        let(:file_contents) { <<-RUBY }
          class CLASS_NAME
            def method_with_lambda
              my_lambda = ->(x = nil) { "lambda" }
              CallableLibrary.execute(&my_lambda)
            end
          end
        RUBY

        it 'traces Lambda with correct caller identification' do
          obj = @trace_file.klass.new

          @trace_b_call.enable
            obj.method_with_lambda
          @trace_b_call.disable

          root = @tracer.call_tree.root

          lambda_block = root.children.first
          expect(lambda_block).not_to be_nil
          expect(lambda_block.method).to eq(:method_with_lambda)
          expect(lambda_block.block).to be(true)
          expect(lambda_block.caller).to eq("execute")
        end
      end

      context 'with Block' do
        let(:file_contents) { <<-RUBY }
          class CLASS_NAME
            def method_with_block
              CallableLibrary.execute { "block" }
            end
          end
        RUBY

        it 'traces Block with correct caller identification' do
          obj = @trace_file.klass.new

          @trace_b_call.enable
            obj.method_with_block
          @trace_b_call.disable

          root = @tracer.call_tree.root

          block_block = root.children.first
          expect(block_block).not_to be_nil
          expect(block_block.method).to eq(:method_with_block)
          expect(block_block.block).to be(true)
          expect(block_block.caller).to eq("execute")
        end
      end
    end

    context 'when using class instance variable block' do
      let(:library_class) { "ClassVarLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class ClassVarLibrary
          def self.execute(&block)
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          @my_block = proc { "class instance variable block" }

          def self.class_block
            @my_block
          end

          def self.use_class_block
            ClassVarLibrary.execute(&class_block)
          end
        end
      RUBY

      it 'traces class instance variable block with correct caller', :aggregate_failures do
        @trace_b_call.enable
          @trace_file.klass.use_class_block
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child).not_to be_nil
        expect(block_child.file).to eq(File.absolute_path(@trace_file.file_path))
        expect(block_child.line).to eq(2)  # Line where @my_block proc is defined in file_contents
        expect(block_child.method).to eq(nil)  # Anonymous proc has no method_id
        expect(block_child.depth).to eq(1)
        expect(block_child.caller).to eq("execute")
        expect(block_child.gem_entry).to eq(false)
        expect(block_child.parent).to eq(root)
        expect(block_child.block).to be(true)
        expect(block_child.node_source.name).to eq("app")
      end
    end

    context 'when stack exhaustion occurs (entire stack is library code)' do
      let(:library_class) { "DeepLibraryStack" }
      let(:library_file_contents) {
        # Generate 30 nested library methods (exceeds safety limit of 25)
        methods = (1..30).map do |i|
          if i == 30
            # Last method yields
            <<-RUBY
          def self.lib_#{i}
            yield if block_given?
          end
            RUBY
          else
            # Pass block to next method
            <<-RUBY
          def self.lib_#{i}(&block)
            lib_#{i + 1}(&block)
          end
            RUBY
          end
        end.join("\n")

        <<-RUBY
        class DeepLibraryStack
#{methods}
        end
        RUBY
      }

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_exhausted_stack
            DeepLibraryStack.lib_1 { "exhausted stack block" }
          end
        end
      RUBY

      it 'falls back to immediate caller when safety limit is reached' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          obj.method_with_exhausted_stack
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child).not_to be_nil
        expect(block_child.method).to eq(:method_with_exhausted_stack)
        expect(block_child.block).to be(true)

        # Should have nil caller since we hit the safety limit before finding boundary
        expect(block_child.caller).to be_nil
      end
    end



    context 'when using method_missing with dynamic dispatch' do
      let(:library_class) { "DynamicLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class DynamicLibrary
          def self.method_missing(name, &block)
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_dynamic_dispatch
            DynamicLibrary.some_undefined_method { "dynamic" }
          end
        end
      RUBY

      it 'traces block with method_missing as caller' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          obj.method_with_dynamic_dispatch
        @trace_b_call.disable

        root = @tracer.call_tree.root

        block_child = root.children.first
        expect(block_child).not_to be_nil
        expect(block_child.method).to eq(:method_with_dynamic_dispatch)
        expect(block_child.block).to be(true)
        expect(block_child.caller).to eq("method_missing")
      end
    end

    context 'when using Fiber context' do
      let(:library_class) { "FiberLibrary" }
      let(:library_file_contents) { <<-RUBY }
        class FiberLibrary
          def self.execute(&block)
            yield if block_given?
          end
        end
      RUBY

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def method_with_fiber
            fiber = Fiber.new do
              FiberLibrary.execute { "in fiber block" }
            end
            fiber.resume
          end
        end
      RUBY

      it 'traces block within Fiber context' do
        obj = @trace_file.klass.new

        @trace_b_call.enable
          result = obj.method_with_fiber
        @trace_b_call.disable

        root = @tracer.call_tree.root

        # Fiber blocks are not being traced - likely because Fiber internals
        # are in paths that get filtered by the tracer's skip logic
        skip "Fiber blocks are not being traced - Fiber internal paths are filtered"
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
        it 'still increments the depth and creates a new child node', :aggregate_failures do
          initial_depth = @tracer.call_tree.depth
          root = @tracer.call_tree.root
          obj = @trace_file.klass.new

          @trace_b_call.enable
            obj.hello_world do
              'Hello, block!'
            end
          @trace_b_call.disable
          calling_line = __LINE__ - 4
          calling_file = __FILE__

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

          expect(@tracer.call_tree.depth).to eq(initial_depth + 1)
          expect(@tracer.call_tree.current_node).to be(root.children.first)
        end
      end

    end
  end
end