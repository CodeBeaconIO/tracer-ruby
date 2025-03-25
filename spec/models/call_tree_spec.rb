require 'spec_helper'

RSpec.describe Codebeacon::Tracer::CallTree do
  let(:call_tree) { Codebeacon::Tracer::CallTree.new(Thread.current) }

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
end
