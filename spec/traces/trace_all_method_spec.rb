# What if 5 calls are made and an error is raised? Do we get 5 returns as the error propagates? I assume that's not the case and what actually happens is that we jump further up the stack without our tracepoints registering anything. This is a problem wherever errors are propogated up the stack and eventually caught.
# ohhhh what about gotos?

require 'spec_helper'

RSpec.describe Codebeacon::Tracer do
  let(:file_contents) { <<-RUBY }
    class CLASS_NAME
      def hello_world
        a = 2
        b = 3
      end
    end
  RUBY

  before do
    @trace_file = TraceFile.new(file_contents)
    @trace_file.require_file
    Codebeacon::Tracer.config.dry_run = true
    Codebeacon::Tracer.config.local_methods_only = false
    Codebeacon::Tracer.config.local_lines_only = true
    @tracer = Codebeacon::Tracer::Tracer.new
    root = @tracer.call_tree.root
    # Line tracing is no longer supported in the new API
    @trace_points = [@tracer.trace_call, @tracer.trace_return]
  end

  after do
    @trace_file.cleanup
  end

  def trace(trace_points, &block)
    trace_points.each(&:enable)
    block.call
  ensure
    trace_points.each(&:disable)
  end

  describe 'full method tracing' do
    context 'happy path' do
      it 'traces a method, its lines and return value', :aggregate_failures do
        obj = @trace_file.klass.new

        trace(@trace_points) { obj.hello_world }

        node = @tracer.call_tree.root.children.first
        expect(node.method).to eq(:hello_world)
        expect(node.return_value).to eq(3)
      end
    end

    context 'with a multi-line expression' do
      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def hello_world
            a = [
              1,2,3,4,
              5,6,7,8,
              9,10,11,12,
              13,14,15,16
            ]
            b = 3
          end
        end
      RUBY

      it 'traces all lines of expression', :aggregate_failures do
        obj = @trace_file.klass.new

        trace(@trace_points) { obj.hello_world }

        node = @tracer.call_tree.root.children.first
        expect(node.method).to eq(:hello_world)
        expect(node.return_value).to eq(3)
      end
    end

    # context 'when the method return value raises an error on "inspect"' do

    #   let(:file_contents) { <<-RUBY }
    #     class CLASS_NAME
    #       def initialize(val)
    #         @val = CannotInspect.new(val)
    #       end

    #       def hello_world
    #         a = @val
    #       end
    #     end
    #   RUBY

    #   it 'uses .to_s to get the return value', :aggregate_failures do
    #     initial_depth = @tracer.call_tree.depth
    #     root = @tracer.call_tree.root
    #     obj = @trace_file.klass.new(999)
    #     trace(@trace_return) { obj.hello_world }

    #     expect(root.lines_executed).to eq(Set.new([8]))
    #     expect(root.linevars).to eq({7=>{}})
    #     expect(root.return_value.to_s).to eq('999')
    #     expect(@tracer.call_tree.depth).to eq(initial_depth - 1)
    #     expect(@tracer.call_tree.current_node).to be(root.parent)
    #   end
    # end

    # context 'when the method return value raises an error on "to_s"' do

    #   let(:file_contents) { <<-RUBY }
    #     class CLASS_NAME
    #       def hello_world
    #         a = CannotToS.new
    #       end
    #     end
    #   RUBY

    #   it 'uses .to_s to get the return value', :aggregate_failures do
    #     initial_depth = @tracer.call_tree.depth
    #     root = @tracer.call_tree.root
    #     obj = @trace_file.klass.new
    #     trace(@trace_return) { obj.hello_world }

    #     expect(root.lines_executed).to eq(Set.new([4]))
    #     expect(root.linevars).to eq({3=>{}})
    #     expect(root.return_value.to_s.downcase).to start_with('--Codebeacon::Tracer Error--'.downcase)
    #     expect(@tracer.call_tree.depth).to eq(initial_depth - 1)
    #     expect(@tracer.call_tree.current_node).to be(root.parent)
    #   end
    # end

    # context 'when an error is raised in the TracePoint while processing the return' do
    #   it 'still decrements the depth and sets the current context to the parent node', :aggregate_failures do
    #     initial_depth = @tracer.call_tree.depth
    #     root = @tracer.call_tree.root
    #     obj = @trace_file.klass.new
    #     allow(root).to receive(:method_end_line).and_raise('Random error')

    #     trace(@trace_return) { obj.hello_world }

    #     expect(root.return_value.to_s.downcase).to start_with('--Codebeacon::Tracer Error--'.downcase)
    #     expect(@tracer.call_tree.depth).to eq(initial_depth - 1)
    #     expect(@tracer.call_tree.current_node).to be(root.parent)
    #   end
    # end
  end
end