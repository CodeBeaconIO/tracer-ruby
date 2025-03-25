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