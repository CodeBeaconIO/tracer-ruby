require 'spec_helper'
require 'sqlite3'

RSpec.describe Codebeacon::Tracer::PersistenceManager do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    @db.results_as_hash = true
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    Codebeacon::Tracer::TreeNodeMapper.create_indexes(@db)
  end
  
  before(:each) do
    @db.execute("DELETE FROM treenodes")
    @db.execute("DELETE FROM node_sources")
    @db.execute("DELETE FROM metadata")
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
  end

  describe '#save_metadata' do
    it 'saves metadata to the database' do
      name = "Test Trace"
      description = "Test Description"
      
      @persistence_manager.save_metadata(name, description)
      
      result = @db.execute("SELECT name, description FROM metadata LIMIT 1").first
      expect(result["name"]).to eq(name)
      expect(result["description"]).to eq(description)
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

  describe '.marshal' do
    it 'truncates long values' do
      long_string = "a" * 2000
      tree_node = Codebeacon::Tracer::TreeNode.new
      
      result = Codebeacon::Tracer::PersistenceManager.marshal("test", long_string, tree_node)
      
      expect(result.length).to be <= Codebeacon::Tracer.config.max_value_length + 1
    end
    
    it 'handles non-string values' do
      value = { key: "value" }
      tree_node = Codebeacon::Tracer::TreeNode.new
      
      result = Codebeacon::Tracer::PersistenceManager.marshal("test", value, tree_node)
      
      expect(result).to include("key")
      expect(result).to include("value")
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
        anything
      )
      
      # Call the method
      persistence_manager.send(:_save_tree, tree_node)
    end
  end
end
