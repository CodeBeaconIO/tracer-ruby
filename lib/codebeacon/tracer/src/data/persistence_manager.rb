require_relative 'tree_node_mapper'
require_relative 'node_source_mapper'
require_relative 'metadata_mapper'

module Codebeacon
  module Tracer
    class PersistenceManager

      def self.marshal(name, value, tree_node)
        begin
          return value.inspect[0..Codebeacon::Tracer.config.max_value_length]
        rescue => e
          begin
            if Codebeacon::Tracer.config.debug?
              Codebeacon::Tracer.logger.warn "Marshal inspect failure - attempting to_s fallback for: \"#{name}\", located at: \"#{tree_node.file}:#{tree_node.line}\"\nerror message: \"#{e.message}\", error_location: \"#{e.backtrace[0]}\""
            end
            return value.to_s[0..Codebeacon::Tracer.config.max_value_length]
          rescue => e
            Codebeacon::Tracer.logger.error "Marshal failure for: \"#{name}\", located at: \"#{tree_node.file}:#{tree_node.line}\"\nerror message: \"#{e.message}\", error_location: \"#{e.backtrace[0]}\""
            return "--Codebeacon::Tracer ERROR-- could not marshall value. See logs."
          end
        end
      end

      def initialize(database)
        @database = database
        @tree_node_mapper = TreeNodeMapper.new(database)
        @node_source_mapper = NodeSourceMapper.new(database)
        @metadata_mapper = MetadataMapper.new(database)
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("nodes persisted")
      end

      def save_metadata(name, description)
        @metadata_mapper.insert(name, description)
      end

      def save_node_sources(node_sources)
        node_sources.each do |node_source|
          next if node_source.nil?
          node_source.id = @node_source_mapper.insert(node_source.name, node_source.root_path)
        end
      end

      def save_trees(trees)
        Codebeacon::Tracer.logger.info("BEGIN db persistence")
        begin
          trees.each do |tree|
            save_tree(tree.root)
          end
        rescue => e
          Codebeacon::Tracer.logger.error("Error during tree persistence: #{e.message}")
          Codebeacon::Tracer.logger.error(e.backtrace.join("\n")) if Codebeacon::Tracer.config.debug?
          # Continue execution without crashing the application
        ensure
          @progress_logger.finish()
          Codebeacon::Tracer.logger.info("END db persistence")
        end
      end

      def save_tree(tree_node, parent_id = nil)
        _save_tree(tree_node, parent_id)
      end

      def _save_tree(tree_node, parent_id = nil)
        @progress_logger.increment
        return if tree_node.nil?

        begin
          node_id = @tree_node_mapper.insert(
            tree_node.file,
            tree_node.line,
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
            _return_value(tree_node)
          )

          unless tree_node.depth_truncated?
            tree_node.children.each do |child|
              _save_tree(child, node_id)
            end
          end
        rescue => e
          Codebeacon::Tracer.logger.error("Error saving tree node: #{e.message}")
          Codebeacon::Tracer.logger.error("Node details: file=#{tree_node.file}, line=#{tree_node.line}, method=#{tree_node.method}") if Codebeacon::Tracer.config.debug?
          # Continue with siblings and other nodes without crashing
        end
      end

      def _return_value(node)
        if node.method == :initialize
          return nil
        else
          PersistenceManager.marshal(node.method, node.return_value, node)
        end
      end
    end
  end
end
