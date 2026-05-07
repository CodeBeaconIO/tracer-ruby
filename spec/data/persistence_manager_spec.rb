require 'spec_helper'
require 'sqlite3'

RSpec.describe Codebeacon::Tracer::PersistenceManager do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    @db.results_as_hash = true
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    Codebeacon::Tracer::BoundaryCallerMapper.create_table(@db)
    Codebeacon::Tracer::CaptureMapper.create_table(@db)
    Codebeacon::Tracer::TreeNodeMapper.create_indexes(@db)
    Codebeacon::Tracer::CaptureMapper.create_indexes(@db)
  end

  before(:each) do
    @db.execute("DELETE FROM treenodes")
    @db.execute("DELETE FROM node_sources")
    @db.execute("DELETE FROM metadata")
    @db.execute("DELETE FROM boundary_callers")
    @db.execute("DELETE FROM captures")
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
  end

  describe '#save_metadata' do
    it 'saves enhanced metadata to the database' do
      # Create metadata with caller location
      caller_location = caller_locations(0, 1).first
      metadata = Codebeacon::Tracer::TraceMetadata.new(name: "Enhanced Test", description: "Enhanced Description", caller_location:, trigger_type: "test")
      metadata.finish_trace
      
      @persistence_manager.save_metadata(metadata)
      
      result = @db.execute("SELECT * FROM metadata LIMIT 1").first
      expect(result["name"]).to eq("Enhanced Test")
      expect(result["description"]).to eq("Enhanced Description")
      expect(result["caller_file"]).to be_a(String)
      expect(result["caller_method"]).to be_a(String)
      expect(result["caller_line"]).to be > 0
      expect(result["duration_ms"]).to be_a(Numeric)
    end
  end

  describe '#save_node_sources' do
    it 'saves node sources to the database' do
      app_source = Codebeacon::Tracer::NodeSource.new('app', '/path/to/app')
      gem_source = Codebeacon::Tracer::NodeSource.new('gem', '/path/to/gem')
      
      @persistence_manager.save_node_sources([app_source, gem_source])
      
      expect(app_source.id).not_to be_nil
      expect(gem_source.id).not_to be_nil
      
      result = @db.execute("SELECT name, root_path FROM node_sources WHERE id = ?", app_source.id).first
      expect(result["name"]).to eq('app')
      expect(result["root_path"]).to eq('/path/to/app')
    end
    
    it 'skips nil node sources' do
      app_source = Codebeacon::Tracer::NodeSource.new('app', '/path/to/app')
      
      @persistence_manager.save_node_sources([app_source, nil])
      
      count = @db.execute("SELECT COUNT(*) FROM node_sources").first[0]
      expect(count).to eq(1)
    end
  end


  
  describe '#_save_tree' do
    it 'handles Symbol values correctly' do
      # Create a tree node with Symbol values
      tree_node = Codebeacon::Tracer::TreeNode.new(
        file: "test_file.rb",
        line: 10,
        method: :test_method,
        self_type: :Class
      )
      
      # Create a mock tree_node_mapper
      tree_node_mapper = double("TreeNodeMapper")
      allow(tree_node_mapper).to receive(:insert).and_return(1)
      
      # Set the tree_node_mapper on the persistence manager
      persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
      persistence_manager.instance_variable_set(:@tree_node_mapper, tree_node_mapper)
      
      # Expect the insert method to be called with string values, not symbols
      expect(tree_node_mapper).to receive(:insert).with(
        tree_node.file,
        tree_node.line,
        tree_node.called_method, # called_method parameter (can be nil)
        "test_method", # String, not Symbol
        anything,
        anything,
        anything,
        "Class", # String, not Symbol
        anything,
        anything,
        anything,
        anything,
        anything,
        anything,
        anything, # has_children parameter
        anything  # library_call_id parameter
      )
      
      # Call the method
      persistence_manager.send(:_save_tree, tree_node)
    end

    it 'handles basic tree node saving' do
      # Create a simple tree node
      tree_node = Codebeacon::Tracer::TreeNode.new(
        file: "test_file.rb",
        line: 10,
        method: "test_method",
        self_type: "Class"
      )
      
      # Save the tree node
      @persistence_manager.save_tree(tree_node)
      
      # Check that it was saved
      result = @db.execute("SELECT * FROM treenodes LIMIT 1").first
      expect(result).not_to be_nil
      expect(result["method"]).to eq("test_method")
      expect(result["self_type"]).to eq("Class")
    end

    it 'writes a return capture for non-initialize methods' do
      tree_node = Codebeacon::Tracer::TreeNode.new(
        file: "test_file.rb",
        line: 10,
        method: "do_thing",
        self_type: "Class",
        return_value: 42
      )

      @persistence_manager.save_tree(tree_node)

      rows = @db.execute("SELECT name, var_type, data_type, inspect FROM captures")
      expect(rows.length).to eq(1)
      row = rows.first
      expect(row["name"]).to be_nil
      expect(row["var_type"]).to eq("return")
      expect(row["data_type"]).to eq("Integer")
      expect(row["inspect"]).to eq("42")
    end

    it 'skips the return capture for :initialize' do
      tree_node = Codebeacon::Tracer::TreeNode.new(
        file: "test_file.rb",
        line: 10,
        method: :initialize,
        self_type: "Class"
      )

      @persistence_manager.save_tree(tree_node)

      count = @db.execute("SELECT COUNT(*) FROM captures").first[0]
      expect(count).to eq(0)
    end

    it 'writes arg captures alongside the return capture' do
      tree_node = Codebeacon::Tracer::TreeNode.new(
        file: "test_file.rb",
        line: 10,
        method: "do_thing",
        self_type: "Class",
        locals: [["count", 7], ["greeting", "hello"]],
        return_value: nil
      )

      @persistence_manager.save_tree(tree_node)

      rows = @db.execute("SELECT name, var_type, data_type FROM captures ORDER BY id")
      expect(rows.map { |r| r["var_type"] }).to eq(["arg", "arg", "return"])
      expect(rows.map { |r| r["name"] }).to eq(["count", "greeting", nil])
      expect(rows.map { |r| r["data_type"] }).to eq(["Integer", "String", "NilClass"])
    end

    it 'handles tree node with called_method that differs from method' do
      # Create a tree node where called_method differs from method
      tree_node = Codebeacon::Tracer::TreeNode.new(
        file: "test_file.rb",
        line: 10,
        method: "original_method",
        called_method: "aliased_method",
        self_type: "Class"
      )
      
      # Save the tree node
      @persistence_manager.save_tree(tree_node)
      
      # Check that both method and called_method were saved correctly
      result = @db.execute("SELECT method, called_method FROM treenodes LIMIT 1").first
      expect(result).not_to be_nil
      expect(result["method"]).to eq("original_method")
      expect(result["called_method"]).to eq("aliased_method")
    end
  end
end
