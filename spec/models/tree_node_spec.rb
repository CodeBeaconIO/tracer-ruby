require 'spec_helper'

RSpec.describe Codebeacon::Tracer::TreeNode do
  describe '#initialize' do
    it 'creates a new instance of Codebeacon::Tracer::TreeNode' do
      node = Codebeacon::Tracer::TreeNode.new
      expect(node).to be_an_instance_of(Codebeacon::Tracer::TreeNode)
    end

    it 'sets the attributes correctly' do
      node = Codebeacon::Tracer::TreeNode.new(file: 'example.rb', line: 10, method: 'example_method')
      expect(node.file).to eq('example.rb')
      expect(node.line).to eq(10)
      expect(node.method).to eq('example_method')
    end

    it 'sets called_method correctly' do
      node = Codebeacon::Tracer::TreeNode.new(called_method: "test_called_method")
      expect(node.called_method).to eq("test_called_method")
    end

    it 'defaults called_method to nil' do
      node = Codebeacon::Tracer::TreeNode.new
      expect(node.called_method).to be_nil
    end

    it 'initializes has_children to false' do
      node = Codebeacon::Tracer::TreeNode.new
      expect(node.has_children).to be false
    end
  end

  describe '#add_child' do
    let(:parent_node) { Codebeacon::Tracer::TreeNode.new }
    let(:child_node) { Codebeacon::Tracer::TreeNode.new }

    it 'adds a child to the parent node' do
      parent_node.add_child(child_node)
      expect(parent_node.children).to include(child_node)
    end

    it 'sets the parent reference on the child node' do
      parent_node.add_child(child_node)
      expect(child_node.parent).to eq(parent_node)
    end

    it 'sets has_children to true when a child is added' do
      expect { parent_node.add_child(child_node) }.to change { parent_node.has_children }.from(false).to(true)
    end

    it 'keeps has_children true when additional children are added' do
      parent_node.add_child(child_node)
      second_child = Codebeacon::Tracer::TreeNode.new
      expect { parent_node.add_child(second_child) }.not_to change { parent_node.has_children }
      expect(parent_node.has_children).to be true
    end
  end

  describe '#add_line' do
    it 'adds a line number and variables to the node' do
      node = Codebeacon::Tracer::TreeNode.new
      node.add_line(5, { var1: 'value1', var2: 'value2' })
      expect(node.linevars[5]).to eq({ var1: 'value1', var2: 'value2' })
    end
  end

  describe '#to_h' do
    it 'returns a hash representation of the node' do
      node = Codebeacon::Tracer::TreeNode.new(file: 'example.rb', line: 10, method: 'example_method')
      hash = node.to_h
      expect(hash[:file]).to eq('example.rb')
      expect(hash[:line]).to eq(10)
      expect(hash[:method]).to eq('example_method')
      expect(hash[:gemEntry]).to eq(false)
      expect(hash[:children]).to be_an(Array)
      expect(hash[:hasChildren]).to be false
    end

    it 'includes hasChildren in the hash representation' do
      node = Codebeacon::Tracer::TreeNode.new
      child = Codebeacon::Tracer::TreeNode.new
      node.add_child(child)
      
      hash = node.to_h
      expect(hash[:hasChildren]).to be true
    end
  end

  describe '#depth_truncated?' do
    it 'returns true if the depth is greater than MAX_DEPTH and has children' do
      max_depth = Codebeacon::Tracer.config.max_depth
      node = Codebeacon::Tracer::TreeNode.new(depth: max_depth + 1)
      node.children << Codebeacon::Tracer::TreeNode.new
      expect(node.depth_truncated?).to be true
    end

    it 'returns false if the depth is less than to MAX_DEPTH' do
      max_depth = Codebeacon::Tracer.config.max_depth
      node = Codebeacon::Tracer::TreeNode.new(depth: max_depth - 1)
      node.children << Codebeacon::Tracer::TreeNode.new
      expect(node.depth_truncated?).to be false
    end

    it 'returns false if the depth is equal to MAX_DEPTH' do
      max_depth = Codebeacon::Tracer.config.max_depth
      node = Codebeacon::Tracer::TreeNode.new(depth: max_depth)
      node.children << Codebeacon::Tracer::TreeNode.new
      expect(node.depth_truncated?).to be false
    end

    it 'returns false if the depth is greater than MAX_DEPTH but the node has no children' do
      max_depth = Codebeacon::Tracer.config.max_depth
      node = Codebeacon::Tracer::TreeNode.new(depth: max_depth + 1)
      expect(node.depth_truncated?).to be false
    end
  end
end