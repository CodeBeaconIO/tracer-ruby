require 'spec_helper'

RSpec.describe Codebeacon::Tracer::NodeBuilder do
  let(:call_tree) { Codebeacon::Tracer::CallTree.new(Thread.current) }

  describe '.trace_method_call' do
    it 'sets called_method when method name differs from method_id' do
      # Create a mock TracePoint where tp.method != tp.method_id
      tp = double("TracePoint")
      allow(tp).to receive(:path).and_return("/test/file.rb")
      allow(tp).to receive(:lineno).and_return(10)
      allow(tp).to receive(:method).and_return(:aliased_method)
      allow(tp).to receive(:method_id).and_return(:original_method)
      allow(tp).to receive(:self).and_return(double("Object", object_id: 123))
      
      # Mock TPKlass
      klass = double("TPKlass")
      allow(klass).to receive(:tp_class).and_return("TestClass")
      allow(klass).to receive(:defined_class).and_return("TestDefinedClass")
      allow(klass).to receive(:tp_class_name).and_return("TestClassName")
      allow(klass).to receive(:type).and_return("Object")
      allow(Codebeacon::Tracer::TPKlass).to receive(:new).and_return(klass)
      
      # Mock NodeSource.find
      allow(Codebeacon::Tracer::NodeSource).to receive(:find).and_return(nil)
      
      # Mock configuration
      allow(Codebeacon::Tracer.config).to receive(:gem_path).and_return("")
      
      # Call the method
      Codebeacon::Tracer::NodeBuilder.trace_method_call(call_tree, tp, "")
      
      # Check that called_method was set correctly
      node = call_tree.current_node
      expect(node.method).to eq(:original_method)
      expect(node.called_method).to eq("aliased_method")
    end

    it 'does not set called_method when method name equals method_id' do
      # Create a mock TracePoint where tp.method == tp.method_id
      tp = double("TracePoint")
      allow(tp).to receive(:path).and_return("/test/file.rb")
      allow(tp).to receive(:lineno).and_return(10)
      allow(tp).to receive(:method).and_return(:same_method)
      allow(tp).to receive(:method_id).and_return(:same_method)
      allow(tp).to receive(:self).and_return(double("Object", object_id: 123))
      
      # Mock TPKlass
      klass = double("TPKlass")
      allow(klass).to receive(:tp_class).and_return("TestClass")
      allow(klass).to receive(:defined_class).and_return("TestDefinedClass")
      allow(klass).to receive(:tp_class_name).and_return("TestClassName")
      allow(klass).to receive(:type).and_return("Object")
      allow(Codebeacon::Tracer::TPKlass).to receive(:new).and_return(klass)
      
      # Mock NodeSource.find
      allow(Codebeacon::Tracer::NodeSource).to receive(:find).and_return(nil)
      
      # Mock configuration
      allow(Codebeacon::Tracer.config).to receive(:gem_path).and_return("")
      
      # Call the method
      Codebeacon::Tracer::NodeBuilder.trace_method_call(call_tree, tp, "")
      
      # Check that called_method was not set
      node = call_tree.current_node
      expect(node.method).to eq(:same_method)
      expect(node.called_method).to be_nil
    end
  end

  describe '.trace_block_call' do
    it 'sets called_method when method name differs from method_id for blocks' do
      # Create a mock TracePoint where tp.method != tp.method_id
      tp = double("TracePoint")
      allow(tp).to receive(:path).and_return("/test/file.rb")
      allow(tp).to receive(:lineno).and_return(10)
      allow(tp).to receive(:method).and_return(:aliased_block_method)
      allow(tp).to receive(:method_id).and_return(:original_block_method)
      allow(tp).to receive(:self).and_return(double("Object", object_id: 123))
      
      # Mock TPKlass
      klass = double("TPKlass")
      allow(klass).to receive(:tp_class).and_return("TestClass")
      allow(klass).to receive(:defined_class).and_return("TestDefinedClass")
      allow(klass).to receive(:tp_class_name).and_return("TestClassName")
      allow(klass).to receive(:type).and_return("Object")
      allow(Codebeacon::Tracer::TPKlass).to receive(:new).and_return(klass)
      
      # Mock NodeSource.find
      allow(Codebeacon::Tracer::NodeSource).to receive(:find).and_return(nil)
      
      # Mock configuration
      allow(Codebeacon::Tracer.config).to receive(:gem_path).and_return("")
      
      # Call the method
      Codebeacon::Tracer::NodeBuilder.trace_block_call(call_tree, tp, "")
      
      # Check that called_method was set correctly and block flag is set
      node = call_tree.current_node
      expect(node.method).to eq(:original_block_method)
      expect(node.called_method).to eq("aliased_block_method")
      expect(node.block).to be true
    end
  end
end 