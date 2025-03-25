require 'spec_helper'
require 'sqlite3'

RSpec.describe "Symbol handling in PersistenceManager" do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    @db.results_as_hash = true
    @db.type_translation = true
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    Codebeacon::Tracer::TreeNodeMapper.create_indexes(@db)
  end
  
  before(:each) do
    @db.execute("DELETE FROM treenodes")
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
  end

  it "converts Symbol values to strings before inserting into the database" do
    # Create a tree node with Symbol values
    tree_node = Codebeacon::Tracer::TreeNode.new(
      file: "test_file.rb",
      line: 10,
      method: :test_method,
      self_type: :Class,
      depth: 1
    )
    
    # Save the tree node
    @persistence_manager.save_tree(tree_node)
    
    # Check that the values were saved correctly
    result = @db.execute("SELECT * FROM treenodes LIMIT 1").first
    expect(result).not_to be_nil
    expect(result["method"]).to eq("test_method")
    expect(result["self_type"]).to eq("Class")
  end
  
  it "handles a mix of Symbol and String values" do
    # Create a tree node with a mix of Symbol and String values
    tree_node = Codebeacon::Tracer::TreeNode.new(
      file: "test_file.rb",
      line: 10,
      method: :test_method,
      tp_class: "TestClass",
      tp_defined_class: "TestDefinedClass",
      tp_class_name: "TestClassName",
      self_type: :Class,
      depth: 1,
      caller: "caller_method"
    )
    
    # Save the tree node
    @persistence_manager.save_tree(tree_node)
    
    # Check that the values were saved correctly
    result = @db.execute("SELECT * FROM treenodes LIMIT 1").first
    expect(result).not_to be_nil
    expect(result["method"]).to eq("test_method")
    expect(result["tp_class"]).to eq("TestClass")
    expect(result["tp_defined_class"]).to eq("TestDefinedClass")
    expect(result["tp_class_name"]).to eq("TestClassName")
    expect(result["self_type"]).to eq("Class")
    expect(result["caller"]).to eq("caller_method")
  end
  
  it "handles nil values" do
    # Create a tree node with some nil values
    tree_node = Codebeacon::Tracer::TreeNode.new(
      file: "test_file.rb",
      line: 10,
      method: nil,
      self_type: nil,
      depth: 1
    )
    
    # Save the tree node
    @persistence_manager.save_tree(tree_node)
    
    # Check that the values were saved correctly
    result = @db.execute("SELECT * FROM treenodes LIMIT 1").first
    expect(result).not_to be_nil
    expect(result["method"]).to eq("")
    expect(result["self_type"]).to eq("")
  end
end 