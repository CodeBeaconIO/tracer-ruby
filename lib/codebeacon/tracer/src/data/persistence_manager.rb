# frozen_string_literal: true

require_relative "tree_node_mapper"
require_relative "node_source_mapper"
require_relative "metadata_mapper"
require_relative "type_detector"
require_relative "safe_serializer"

module Codebeacon
  module Tracer
    class PersistenceManager
      def initialize(database)
        @database = database
        @tree_node_mapper = TreeNodeMapper.new(database)
        @node_source_mapper = NodeSourceMapper.new(database)
        @metadata_mapper = MetadataMapper.new(database)
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("nodes persisted")
      end

      def save_metadata(metadata)
        @metadata_mapper.insert(metadata)
      end

      def save_node_sources(node_sources)
        @database.transaction
        node_sources.each do |node_source|
          next if node_source.nil?

          node_source.id = @node_source_mapper.insert(node_source.name, node_source.root_path)
        end
        @database.commit
      rescue StandardError => e
        @database.rollback
        raise e
      end

      def save_trees(trees)
        Codebeacon::Tracer.logger.info("BEGIN db persistence")
        @database.transaction
        trees.each do |tree|
          save_tree(tree.root)
        end
      rescue StandardError => e
        Codebeacon::Tracer.logger.error("Error during tree persistence: #{e.message}")
        Codebeacon::Tracer.logger.error(e.backtrace.join("\n")) if Codebeacon::Tracer.config.debug?
        @database.rollback
        # Continue execution without crashing the application
      ensure
        @database.commit
        @tree_node_mapper.close_statement
        @progress_logger.decrement() # Do not count the root node which is in addition to the traced nodes
        @progress_logger.finish()
        Codebeacon::Tracer.logger.info("END db persistence")
      end

      def save_tree(tree_node, parent_id = nil)
        # This is a placeholder for the original recursive saving logic
        # that will now be executed within a single transaction.
        _save_tree(tree_node, parent_id)
      end

      def _save_tree(tree_node, parent_id = nil)
        @progress_logger.increment
        return if tree_node.nil?

        node_id = @tree_node_mapper.insert(
          tree_node.file,
          tree_node.line,
          tree_node.called_method&.to_s, # Convert symbols to strings, keep nil as nil
          tree_node.method.to_s,
          tree_node.tp_class.to_s,
          tree_node.tp_defined_class.to_s,
          tree_node.tp_class_name.to_s,
          tree_node.self_type.to_s,
          tree_node.depth,
          tree_node.caller,
          tree_node.gem_entry,
          parent_id,
          tree_node.block,
          tree_node.node_source&.id,
          return_type(tree_node),
          return_value(tree_node),
          tree_node.has_children
        )

        return if tree_node.depth_truncated?

        tree_node.children.each do |child|
          _save_tree(child, node_id)
        end
      rescue StandardError => e
        Codebeacon::Tracer.logger.error("Error saving tree node: #{e.message}")
        if Codebeacon::Tracer.config.debug?
          Codebeacon::Tracer.logger.error("Node details: file=#{tree_node.file}, line=#{tree_node.line}, method=#{tree_node.method}")
        end
        # Continue with siblings and other nodes without crashing
      end

      private

      def return_type(node)
        return nil if node.method == :initialize

        node.return_value.class.name
      end

      def return_value(node)
        return nil if node.method == :initialize

        SafeSerializer.serialize(node.return_value, Codebeacon::Tracer.config.max_value_length)
      end
    end
  end
end
