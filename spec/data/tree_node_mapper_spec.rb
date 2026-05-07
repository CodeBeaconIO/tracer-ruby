require 'spec_helper'
require 'sqlite3'

RSpec.describe Codebeacon::Tracer::TreeNodeMapper do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::BoundaryCallerMapper.create_table(@db)
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
      called_method = "test_called_method"
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
      has_children = true

      node_id = @mapper.insert(
        file, line, called_method, method, tp_class, tp_defined_class, tp_class_name,
        self_type, depth, caller, gem_entry, parent_id, block, node_source_id, has_children, nil
      )

      expect(node_id).to be_a(Integer)

      result = @db.execute("SELECT * FROM treenodes WHERE id = ?", node_id).first
      expect(result).not_to be_nil
      expect(result[1]).to eq(file)
      expect(result[2]).to eq(line)
      expect(result[3]).to eq(called_method)
      expect(result[4]).to eq(method)
      expect(result[5]).to eq(tp_class)
      expect(result[6]).to eq(tp_defined_class)
      expect(result[7]).to eq(tp_class_name)
      expect(result[8]).to eq(self_type)
      expect(result[9]).to eq(depth)
      expect(result[10]).to eq(caller)
      expect(result[11]).to eq(1) # gem_entry as integer
      expect(result[12]).to be_nil # parent_id
      expect(result[13]).to eq(0) # block as integer
      expect(result[14]).to eq(node_source_id)
      expect(result[15]).to eq(1) # has_children as integer
    end

    it 'inserts a tree node with a parent' do
      parent_id = @mapper.insert(
        "parent.rb", 1, "parent_called_method", "parent_method", "ParentClass", "ParentDefinedClass",
        "ParentClassName", "Object", 0, "parent_caller", false, nil, false, nil, true, nil
      )

      child_id = @mapper.insert(
        "child.rb", 2, "child_called_method", "child_method", "ChildClass", "ChildDefinedClass",
        "ChildClassName", "Object", 1, "child_caller", false, parent_id, false, nil, false, nil
      )

      result = @db.execute("SELECT parent_id FROM treenodes WHERE id = ?", child_id).first
      expect(result[0]).to eq(parent_id)
    end

    it 'inserts a tree node with a called_method' do
      called_method_id = @mapper.insert(
        "called_method.rb", 1, "called_method_called", "called_method_method", "CalledMethodClass", "CalledMethodDefinedClass",
        "CalledMethodClassName", "Object", 0, "called_method_caller", false, nil, false, nil, false, nil
      )

      caller_id = @mapper.insert(
        "caller.rb", 2, "caller_called_method", "caller_method", "CallerClass", "CallerDefinedClass",
        "CallerClassName", "Object", 1, "caller_caller", false, nil, false, nil, true, nil
      )

      result = @db.execute("SELECT called_method FROM treenodes WHERE id = ?", caller_id).first
      expect(result[0]).to eq("caller_called_method")
    end

    it 'correctly stores has_children flag' do
      node_with_children = @mapper.insert(
        "with_children.rb", 1, "method", "method", "Class", "Class", "ClassName", "Object", 0, "caller",
        false, nil, false, nil, true, nil
      )

      node_without_children = @mapper.insert(
        "without_children.rb", 1, "method", "method", "Class", "Class", "ClassName", "Object", 0, "caller",
        false, nil, false, nil, false, nil
      )

      with_children_result = @db.execute("SELECT has_children FROM treenodes WHERE id = ?", node_with_children).first
      without_children_result = @db.execute("SELECT has_children FROM treenodes WHERE id = ?", node_without_children).first

      expect(with_children_result[0]).to eq(1)
      expect(without_children_result[0]).to eq(0)
    end
  end

  describe '.create_table' do
    it 'creates the treenodes table with has_children column' do
      db = SQLite3::Database.new ":memory:"
      Codebeacon::Tracer::TreeNodeMapper.create_table(db)
      
      columns = db.execute("PRAGMA table_info(treenodes)").map { |row| row[1] }
      expect(columns).to include("has_children")
    end
  end

  describe '.create_indexes' do
    it 'creates an index on has_children column' do
      db = SQLite3::Database.new ":memory:"
      Codebeacon::Tracer::TreeNodeMapper.create_table(db)
      Codebeacon::Tracer::TreeNodeMapper.create_indexes(db)
      
      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='treenodes'").map { |row| row[0] }
      expect(indexes).to include("IDX_treenode_has_children")
    end
  end
end
