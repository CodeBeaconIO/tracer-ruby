require 'spec_helper'

RSpec.describe Codebeacon::Tracer::CallTree do
  let(:call_tree) { Codebeacon::Tracer::CallTree.new(Thread.current) }

  before do
    # Reset thread ID counter for test isolation
    Codebeacon::Tracer::CallTree.instance_variable_set(:@thread_id, 0)
  end

  describe '#initialize' do
    it 'initializes with a root node' do
      expect(call_tree.root).to be_a(Codebeacon::Tracer::TreeNode)
      expect(call_tree.root.method).to eq("thread (1)")
    end

    it 'sets the initial depth to 0' do
      expect(call_tree.depth).to eq(0)
    end

    it 'initializes the call count to 0' do
      expect(call_tree.call_count).to eq(0)
    end

    it 'initializes the block call count to 0' do
      expect(call_tree.block_call_count).to eq(0)
    end

    it 'returns 0 for total_call_count' do
      expect(call_tree.total_call_count).to eq(0)
    end

    it 'sets current_node to root' do
      expect(call_tree.current_node).to eq(call_tree.root)
    end

    it 'initializes root node with has_children set to false' do
      expect(call_tree.root.has_children).to be false
    end
  end

  describe '#total_call_count' do
    it 'returns the sum of call_count and block_call_count' do
      call_tree.add_call
      call_tree.add_block_call
      expect(call_tree.total_call_count).to eq(2)
    end
  end

  describe '#add_call' do
    it 'increments the call count' do
      expect { call_tree.add_call }.to change { call_tree.call_count }.by(1)
    end

    it 'adds a new node to the current node children' do
      expect { call_tree.add_call }.to change { call_tree.root.children.size }.by(1)
    end

    it 'increases the depth by 1' do
      expect { call_tree.add_call }.to change { call_tree.depth }.by(1)
    end

    it 'updates the current node to the new node' do
      call_tree.add_call
      expect(call_tree.current_node).not_to eq(call_tree.root)
      expect(call_tree.current_node.parent).to eq(call_tree.root)
    end

    it 'sets has_children flag on the parent node' do
      expect { call_tree.add_call }.to change { call_tree.root.has_children }.from(false).to(true)
    end
  end

  describe '#add_block_call' do
    it 'increments the block call count' do
      expect { call_tree.add_block_call }.to change { call_tree.block_call_count }.by(1)
    end

    it 'adds a new node to the current node children' do
      expect { call_tree.add_block_call }.to change { call_tree.root.children.size }.by(1)
    end

    it 'increases the depth by 1' do
      expect { call_tree.add_block_call }.to change { call_tree.depth }.by(1)
    end

    it 'updates the current node to the new node' do
      call_tree.add_block_call
      expect(call_tree.current_node).not_to eq(call_tree.root)
      expect(call_tree.current_node.parent).to eq(call_tree.root)
    end

    it 'sets has_children flag on the parent node' do
      expect { call_tree.add_block_call }.to change { call_tree.root.has_children }.from(false).to(true)
    end
  end

  describe '#add_return' do
    before do
      call_tree.add_call
      call_tree.add_block_call
    end

    it 'decreases the depth by 1' do
      expect { call_tree.add_return }.to change { call_tree.depth }.by(-1)
    end

    it 'sets the current node to its parent' do
      parent_node = call_tree.current_node.parent
      call_tree.add_return
      expect(call_tree.current_node).to eq(parent_node)
    end

    xit 'does not decrease the depth below 0' do
      3.times { call_tree.add_return }
      expect(call_tree.depth).to be >= 0
    end

    it 'does not change current_node if it is already at the root' do
      2.times { call_tree.add_return }
      expect(call_tree.current_node).to eq(call_tree.root)
    end
  end

  describe '#synthesize_pre_trace_return' do
    it 'returns a freshly-built synthetic TreeNode' do
      synth = call_tree.synthesize_pre_trace_return
      expect(synth).to be_a(Codebeacon::Tracer::TreeNode)
      expect(synth.synthetic).to be true
    end

    it 'inserts the synth as the only child of root and leaves current_node at root' do
      synth = call_tree.synthesize_pre_trace_return
      expect(call_tree.root.children).to eq([synth])
      expect(synth.parent).to eq(call_tree.root)
      expect(call_tree.current_node).to eq(call_tree.root)
    end

    it 're-parents existing root children under the synth' do
      call_tree.add_call
      observed = call_tree.current_node
      call_tree.add_return # current back to root
      expect(call_tree.root.children).to eq([observed])

      synth = call_tree.synthesize_pre_trace_return

      expect(call_tree.root.children).to eq([synth])
      expect(synth.children).to eq([observed])
      expect(observed.parent).to eq(synth)
      expect(synth.has_children).to be true
    end

    it 'chains multiple synthetics' do
      call_tree.add_call
      call_tree.add_return
      observed = call_tree.root.children.first

      synth1 = call_tree.synthesize_pre_trace_return
      synth2 = call_tree.synthesize_pre_trace_return

      expect(call_tree.root.children).to eq([synth2])
      expect(synth2.children).to eq([synth1])
      expect(synth1.children).to eq([observed])
    end

    it 'increments synthetic_count without touching call_count or block_call_count' do
      expect {
        call_tree.synthesize_pre_trace_return
      }.to change { call_tree.synthetic_count }.by(1)
        .and change { call_tree.call_count }.by(0)
        .and change { call_tree.block_call_count }.by(0)
    end

    it 'tags synth depth more negative for each successive synthesis' do
      synth1 = call_tree.synthesize_pre_trace_return
      synth2 = call_tree.synthesize_pre_trace_return
      synth3 = call_tree.synthesize_pre_trace_return

      expect(synth1.depth).to eq(-1)
      expect(synth2.depth).to eq(-2)
      expect(synth3.depth).to eq(-3)
    end

    it 'leaves observed-node depths untouched' do
      call_tree.add_call
      observed = call_tree.current_node
      observed.depth = 1 # NodeBuilder normally stamps this; simulate
      call_tree.add_return

      call_tree.synthesize_pre_trace_return

      expect(observed.depth).to eq(1)
    end
  end
end
