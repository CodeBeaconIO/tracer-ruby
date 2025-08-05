require 'spec_helper'

RSpec.describe "Called method integration" do
  before(:each) do
    @db = SQLite3::Database.new(":memory:")
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
    # Clear caches between tests to prevent mock object leakage
    Codebeacon::Tracer::NodeBuilder.clear_caches
  end

  it "records called_method when method is aliased" do
    # Create a class with an aliased method
    test_class = Class.new do
      def original_method
        "original"
      end
      alias_method :aliased_method, :original_method
    end

    # Create a tree node manually to simulate the tracing
    tree_node = Codebeacon::Tracer::TreeNode.new(
      file: "/test/file.rb",
      line: 10,
      method: :original_method,
      called_method: "aliased_method",
      tp_class: "TestClass",
      tp_defined_class: "TestClass",
      tp_class_name: "TestClass",
      self_type: "Object",
      depth: 1,
      caller: "",
      gem_entry: false,
      block: false,
      node_source: nil
    )

    # Save the tree node
    @persistence_manager.save_tree(tree_node)

    # Check the database for the recorded call
    result = @db.execute("SELECT method, called_method FROM treenodes WHERE method = 'original_method'").first
    
    expect(result).not_to be_nil
    expect(result[0]).to eq("original_method") # The actual method
    expect(result[1]).to eq("aliased_method")  # The called method name
  end

  it "does not record called_method when method name matches" do
    # Create a tree node where called_method is nil (same as method)
    tree_node = Codebeacon::Tracer::TreeNode.new(
      file: "/test/file.rb",
      line: 10,
      method: :regular_method,
      called_method: nil, # Same as method, so should be nil
      tp_class: "TestClass",
      tp_defined_class: "TestClass",
      tp_class_name: "TestClass",
      self_type: "Object",
      depth: 1,
      caller: "",
      gem_entry: false,
      block: false,
      node_source: nil
    )

    # Save the tree node
    @persistence_manager.save_tree(tree_node)

    # Check the database for the recorded call
    result = @db.execute("SELECT method, called_method FROM treenodes WHERE method = 'regular_method'").first
    
    expect(result).not_to be_nil
    expect(result[0]).to eq("regular_method") # The method
    expect(result[1]).to be_nil               # The called_method (should be NULL)
  end

  it "demonstrates the NodeBuilder logic with mocked TracePoint" do
    # Create a call tree
    call_tree = Codebeacon::Tracer::CallTree.new(Thread.current)
    
    # Create a mock TracePoint where tp.method != tp.method_id (aliased method)
    tp = double("TracePoint")
    allow(tp).to receive(:path).and_return("/test/file.rb")
    allow(tp).to receive(:lineno).and_return(10)
    allow(tp).to receive(:method).and_return(:aliased_method)
    allow(tp).to receive(:method_id).and_return(:original_method)
    allow(tp).to receive(:callee_id).and_return(:aliased_method)
    allow(tp).to receive(:self).and_return(double("Object", object_id: 123))
    allow(tp).to receive(:defined_class).and_return(double("DefinedClass", object_id: 456))
    
    # Mock TPKlass
    klass = double("TPKlass")
    allow(klass).to receive(:tp_class).and_return("TestClass")
    allow(klass).to receive(:defined_class).and_return("TestClass")
    allow(klass).to receive(:tp_class_name).and_return("TestClass")
    allow(klass).to receive(:type).and_return("Object")
    allow(Codebeacon::Tracer::TPKlass).to receive(:for_tp).and_return(klass)
    
    # Mock NodeSource.find
    allow(Codebeacon::Tracer::NodeSource).to receive(:find).and_return(nil)
    
    # Mock configuration
    allow(Codebeacon::Tracer.config).to receive(:gem_path).and_return("")
    
    # Call the NodeBuilder method
    Codebeacon::Tracer::NodeBuilder.trace_method_call(call_tree, tp, "")
    
    # Check that called_method was set correctly
    node = call_tree.current_node
    expect(node.method).to eq(:original_method)
    expect(node.called_method).to eq(:aliased_method) # NodeBuilder sets Symbol
    
    # Now test with a regular method (no alias)
    call_tree2 = Codebeacon::Tracer::CallTree.new(Thread.current)
    tp2 = double("TracePoint")
    allow(tp2).to receive(:path).and_return("/test/file.rb")
    allow(tp2).to receive(:lineno).and_return(10)
    allow(tp2).to receive(:method).and_return(:regular_method)
    allow(tp2).to receive(:method_id).and_return(:regular_method)
    allow(tp2).to receive(:callee_id).and_return(:regular_method)
    allow(tp2).to receive(:self).and_return(double("Object", object_id: 123))
    
    allow(Codebeacon::Tracer::TPKlass).to receive(:for_tp).and_return(klass)
    allow(Codebeacon::Tracer::NodeSource).to receive(:find).and_return(nil)
    allow(Codebeacon::Tracer.config).to receive(:gem_path).and_return("")
    
    Codebeacon::Tracer::NodeBuilder.trace_method_call(call_tree2, tp2, "")
    
    # Check that called_method was not set
    node2 = call_tree2.current_node
    expect(node2.method).to eq(:regular_method)
    expect(node2.called_method).to be_nil
  end
end 