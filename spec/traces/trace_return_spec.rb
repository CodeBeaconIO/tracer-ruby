require 'spec_helper'
# TODO - should record empty nodes (or error nodes) on call or return error. I believe currently, it either does not push or pop a node. That means that if the call succeeds but the return fails, then we end up one level too far down for subsequent requetss. If the call fails but the return succeeds, then we end up oen level too far up for the rest of the calls.
#        or perhaps we should register an error on call so that return knows not to pop. On return failure we could be sure to remove or modify the corresponding call node. This would require that we do more to verify that the call and return are properly paired together. Adding this level of validation may be nice to have on its own in case there are weird timing issues or some other errors that cause an issue. For instance, what if 5 calls are made and an error is raised? Do we get 5 returns as the error propagates?
# TODO - raise errors in debug mode instead of warning? or add a test mode where that's the case? Because certain errors we may not have control over to fix, like the to_s and inspect
# TODO - be sure to test methods all on the same line - perhaps all of the permutations that exist in the ast_wrangler spec?
# TODO - 1. wrap the current logger with my own custom class
#        2. add some debug methods that take the current tracepoint, tracks counts and add lots of logs. Purpose to get logging out of the tracepoint hooks

RSpec.describe Codebeacon::Tracer do
  let(:file_contents) { <<-RUBY }
    class CLASS_NAME
      def hello_world
        a = 2
      end
    end
  RUBY

  before do
    @trace_file = TraceFile.new(file_contents)
    @trace_file.require_file
    Codebeacon::Tracer.config.dry_run = true
    Codebeacon::Tracer.config.local_methods_only = true
    Codebeacon::Tracer.config.local_lines_only = true
    @tracer = Codebeacon::Tracer::Tracer.new
    root = @tracer.call_tree.root
    root.parent = Codebeacon::Tracer::TreeNode.new
    @trace_return = @tracer.trace_return
  end

  after do
    @trace_file.cleanup
  end

  def trace(trace_point, &block)
    trace_point.enable
    block.call
  ensure
    trace_point.disable
  end

  describe '.trace_return' do
    context 'happy path' do
      it 'traces a method', :aggregate_failures do
        initial_depth = @tracer.call_tree.depth
        root = @tracer.call_tree.root
        obj = @trace_file.klass.new

        trace(@trace_return) { obj.hello_world }

        expect(root.return_value.to_s).to eq('2')
        expect(@tracer.call_tree.depth).to eq(initial_depth - 1)
        expect(@tracer.call_tree.current_node).to be(root.parent)
      end
    end

    context 'when the method return value raises an error on "inspect"' do

      let(:file_contents) { <<-RUBY }
        class CLASS_NAME
          def initialize(val)
            @val = CannotInspect.new(val)
          end

          def hello_world
            a = @val
          end
        end
      RUBY

      it 'uses .to_s to get the return value', :aggregate_failures do
        initial_depth = @tracer.call_tree.depth
        root = @tracer.call_tree.root
        obj = @trace_file.klass.new(999)
        trace(@trace_return) { obj.hello_world }

        expect(root.return_value.to_s).to eq('999')
        expect(@tracer.call_tree.depth).to eq(initial_depth - 1)
        expect(@tracer.call_tree.current_node).to be(root.parent)
      end
    end

    context 'when not in debug mode' do
      around do |example|
        original_debug = Codebeacon::Tracer.config.debug?
        Codebeacon::Tracer.config.debug = false
        example.run
        Codebeacon::Tracer.config.debug = original_debug
      end
      context 'when an error is raised in the TracePoint while processing the return' do
        it 'still decrements the depth and sets the current context to the parent node', :aggregate_failures do
          initial_depth = @tracer.call_tree.depth
          root = @tracer.call_tree.root
          obj = @trace_file.klass.new
          allow(root).to receive(:trace_status).and_raise('Random error')

          trace(@trace_return) { obj.hello_world }

          expect(root.return_value.to_s.downcase).to start_with('--Codebeacon::Tracer Error--'.downcase)
          expect(@tracer.call_tree.depth).to eq(initial_depth - 1)
          expect(@tracer.call_tree.current_node).to be(root.parent)
        end
      end
    end
  end
end