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
          output += caller.empty? ? "" : " [caller: #{caller}]"
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
    end
  end
end
