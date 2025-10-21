# frozen_string_literal: true

# Monkey patch TreeNode to add debugging helper methods for specs
module Codebeacon
  module Tracer
    class TreeNode
      def simple_print(depth = 0, show: [])
        indent = "  " * depth
        method_name = method || "(anonymous)"

        output = if block
                   "#{indent}λ #{method_name}"
                 else
                   "#{indent}#{method_name}"
                 end

        # Add optional fields based on show array
        if show.include?(:caller)
          output += (caller.nil? || caller.empty?) ? "" : " [caller: #{caller}]"
        end

        if show.include?(:callback_info)
          output += callback_info ? " [callback: #{callback_info[:outgoing_method]}]" : ""
        end

        if show.include?(:boundary_caller_id)
          output += boundary_caller_id ? " [boundary_caller_id: #{boundary_caller_id}]" : ""
        end

        puts output

        children.each do |child|
          child.simple_print(depth + 1, show: show)
        end
      end

      # Find nodes in the tree matching the specified criteria
      # @param block [Boolean, nil] If true, only find blocks; if false, only find methods; if nil, find both
      # @param method_name [Symbol, nil] Optional method name to filter by
      # @param callback [Boolean, nil] If true, only find nodes with callback_info; if false, only nodes without; if nil, find both
      # @return [Array<TreeNode>] Matching nodes
      def find_nodes(block: nil, method_name: nil, callback: nil)
        nodes = []
        visit_nodes = ->(node) do
          matches = (callback.nil? || (callback ? node.callback_info : !node.callback_info)) &&
                    (block.nil? || node.block == block) &&
                    (method_name.nil? || node.method == method_name)
          nodes << node if matches
          node.children.each { |child| visit_nodes.call(child) }
        end
        visit_nodes.call(self)
        nodes
      end
    end
  end
end
