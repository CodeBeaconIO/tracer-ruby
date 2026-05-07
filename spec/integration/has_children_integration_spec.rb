# frozen_string_literal: true

require 'spec_helper'

RSpec.describe "Has Children Integration" do
  let(:db) { SQLite3::Database.new ":memory:" }
  let(:persistence_manager) { Codebeacon::Tracer::PersistenceManager.new(db) }

  before do
    Codebeacon::Tracer::TreeNodeMapper.create_table(db)
    Codebeacon::Tracer::TreeNodeMapper.create_indexes(db)
    Codebeacon::Tracer::MetadataMapper.create_table(db)
    Codebeacon::Tracer::MetadataMapper.create_indexes(db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(db)
    Codebeacon::Tracer::NodeSourceMapper.create_indexes(db)
    Codebeacon::Tracer::BoundaryCallerMapper.create_table(db)
    Codebeacon::Tracer::BoundaryCallerMapper.create_indexes(db)
    Codebeacon::Tracer::CaptureMapper.create_table(db)
    Codebeacon::Tracer::CaptureMapper.create_indexes(db)
  end

  describe "has_children flag in complete tracing workflow" do
    it "correctly sets and persists has_children flag" do
      # Create a simple call tree with children
      call_tree = Codebeacon::Tracer::CallTree.new(Thread.current)
      
      # Add a call to create a child
      call_tree.add_call
      
      # Verify the root node has children
      expect(call_tree.root.has_children).to be true
      expect(call_tree.root.children.size).to eq(1)
      
      # Verify child node doesn't have children initially
      expect(call_tree.root.children.first.has_children).to be false
      
      # Add a child to the first child node (manually set depth)
      first_child = call_tree.root.children.first
      grandchild = Codebeacon::Tracer::TreeNode.new(depth: 2)
      first_child.add_child(grandchild)
      
      # Verify the first child now has children
      expect(first_child.has_children).to be true
      expect(first_child.children.size).to eq(1)
      
      # Save the tree to database
      persistence_manager.save_trees([call_tree])
      
      # Query the database to verify has_children flags are persisted correctly
      # Since depth is not set on nodes, we'll check by ID order instead
      all_nodes = db.execute("SELECT id, has_children FROM treenodes ORDER BY id")
      
      # Root should have children (first node)
      expect(all_nodes[0][1]).to eq(1) # Root has children
      
      # First child should have children (second node)
      expect(all_nodes[1][1]).to eq(1) # First child has children
      
      # Grandchild should have no children (third node)
      expect(all_nodes[2][1]).to eq(0) # Grandchild has no children
    end

    it "handles nodes without children correctly" do
      # Create a call tree with no additional calls
      call_tree = Codebeacon::Tracer::CallTree.new(Thread.current)
      
      # Verify root node has no children initially
      expect(call_tree.root.has_children).to be false
      expect(call_tree.root.children.size).to eq(0)
      
      # Save the tree to database
      persistence_manager.save_trees([call_tree])
      
      # Query the database to verify has_children flag is false
      root_result = db.execute("SELECT has_children FROM treenodes WHERE depth = 0").first
      expect(root_result[0]).to eq(0) # Root has no children
    end

    it "maintains has_children flag consistency through multiple operations" do
      call_tree = Codebeacon::Tracer::CallTree.new(Thread.current)
      
      # Add a call
      call_tree.add_call
      expect(call_tree.root.has_children).to be true
      expect(call_tree.root.children.size).to eq(1)
      
      # Add a child to the first child (manually set depth)
      first_child = call_tree.root.children.first
      grandchild = Codebeacon::Tracer::TreeNode.new(depth: 2)
      first_child.add_child(grandchild)
      expect(first_child.has_children).to be true
      
      # Save and verify in database
      persistence_manager.save_trees([call_tree])
      
      # Count nodes with and without children
      nodes_with_children = db.execute("SELECT COUNT(*) FROM treenodes WHERE has_children = 1").first[0]
      nodes_without_children = db.execute("SELECT COUNT(*) FROM treenodes WHERE has_children = 0").first[0]
      
      # We should have 2 nodes with children (root and first child) and 1 without (grandchild)
      expect(nodes_with_children).to eq(2)
      expect(nodes_without_children).to eq(1)
    end
  end
end 