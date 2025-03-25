require 'spec_helper'
require 'sqlite3'

RSpec.describe Codebeacon::Tracer::TreeNodeMapper do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::TreeNodeMapper.create_indexes(@db)
  end

  before(:each) do
    @db.execute("DELETE FROM treenodes")
    @mapper = Codebeacon::Tracer::TreeNodeMapper.new(@db)
  end

  describe '#insert' do
    it 'inserts a tree node into the database' do
      file = "test_file.rb"
      line = 10
      method = "test_method"
      tp_class = "TestClass"
      tp_defined_class = "TestDefinedClass"
      tp_class_name = "TestClassName"
      self_type = "Object"
      depth = 1
      caller = "caller_method"
      gem_entry = true
      parent_id = nil
      block = false
      node_source_id = 1
      return_value = "test_return_value"

      node_id = @mapper.insert(
        file, line, method, tp_class, tp_defined_class, tp_class_name, 
        self_type, depth, caller, gem_entry, parent_id, block, node_source_id, return_value
      )

      expect(node_id).to be_a(Integer)

      result = @db.execute("SELECT * FROM treenodes WHERE id = ?", node_id).first
      expect(result).not_to be_nil
      expect(result[1]).to eq(file)
      expect(result[2]).to eq(line)
      expect(result[3]).to eq(method)
      expect(result[4]).to eq(tp_class)
      expect(result[5]).to eq(tp_defined_class)
      expect(result[6]).to eq(tp_class_name)
      expect(result[7]).to eq(self_type)
      expect(result[8]).to eq(depth)
      expect(result[9]).to eq(caller)
      expect(result[10]).to eq(1) # gem_entry as integer
      expect(result[11]).to be_nil # parent_id
      expect(result[12]).to eq(0) # block as integer
      expect(result[13]).to eq(node_source_id)
      expect(result[14]).to eq(return_value)
    end

    it 'inserts a tree node with a parent' do
      parent_id = @mapper.insert(
        "parent.rb", 1, "parent_method", "ParentClass", "ParentDefinedClass", 
        "ParentClassName", "Object", 0, "parent_caller", false, nil, false, nil, nil
      )

      child_id = @mapper.insert(
        "child.rb", 2, "child_method", "ChildClass", "ChildDefinedClass", 
        "ChildClassName", "Object", 1, "child_caller", false, parent_id, false, nil, nil
      )

      result = @db.execute("SELECT parent_id FROM treenodes WHERE id = ?", child_id).first
      expect(result[0]).to eq(parent_id)
    end
  end

  describe '.create_table' do
    it 'creates the treenodes table' do
      result = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='treenodes'")
      expect(result).not_to be_empty
    end

    it 'creates the table with the correct columns' do
      result = @db.execute("PRAGMA table_info(treenodes)")
      column_names = result.map { |col| col[1] }
      
      expected_columns = [
        "id", "file", "line", "method", "tp_class", "tp_defined_class", 
        "tp_class_name", "self_type", "depth", "caller", "gemEntry", 
        "parent_id", "block", "node_source_id", "return_value"
      ]
      
      expected_columns.each do |column|
        expect(column_names).to include(column)
      end
    end
  end

  describe '.create_indexes' do
    it 'creates the parent_id index' do
      result = @db.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='IDX_treenode_parent_id'")
      expect(result).not_to be_empty
    end

    it 'creates the node_source_id index' do
      result = @db.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='IDX_treenode_node_source_id'")
      expect(result).not_to be_empty
    end
  end
end
