require 'spec_helper'

RSpec.describe Codebeacon::Tracer do
  let(:file_contents) { <<-RUBY }
    class CLASS_NAME
      def hello_world
        yield if block_given?
      end
    end
  RUBY

  before do
    Codebeacon::Tracer::NodeSource.new('app', Codebeacon::Tracer.config.root_path)
    @trace_file = TraceFile.load!(file_contents)
    Codebeacon::Tracer.config.dry_run = true
    Codebeacon::Tracer.config.local_methods_only = true
    Codebeacon::Tracer.config.local_lines_only = true
    @tracer = Codebeacon::Tracer::Tracer.new
    @trace_b_call = @tracer.trace_b_call
  end

  after do
    @trace_file.cleanup
  end

  describe '.trace_call' do
    it 'traces a block call' do
      obj = @trace_file.klass.new

      @trace_b_call.enable
        obj.hello_world do
          puts 'Hello, block!'
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
              puts 'Hello, block!'
            end
          @trace_b_call.disable
          calling_line = __LINE__ - 4
          calling_file = __FILE__

          node = root.children.first
          expect(node.file).to eq(File.absolute_path(calling_file))
          expect(node.line).to eq(calling_line)
          expect(node.method).to eq(nil)
          expect(node.depth).to eq(1)
          expect(node.caller).to eq("")
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