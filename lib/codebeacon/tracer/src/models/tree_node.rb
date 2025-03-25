require 'set'

  # store node memory in a format that can be directly loaded 1:1 into sqlite3
  # could use rocksdb or something else
  # could use lmdb
  # could use leveldb
  # actually log if this speeds up developer time - would be really cool to show!
module Codebeacon
  module Tracer
    class TreeNode
      class TraceStatus < Struct.new(:previous_line)
        def any_lines_traced?
          !previous_line.nil?
        end
      end
      # attr_accessor :file, :line, :method, :depth, :caller, :gem_entry, :children, :parent, :block, :locals, :ast, :return_value, :linevars

      # def initialize(file: nil, line: nil, method: nil, depth: 0, caller: "", gem_entry: false, parent: nil, block: false, locals: [], ast: nil, return_value: "")
      #   @file = file
      #   @line = line
      #   @method = method
      #   @depth = depth
      #   @caller = caller
      #   @gem_entry = gem_entry
      #   @parent = parent
      #   @block = block
      #   @locals = locals
      #   @ast = ast
      #   @return_value = return_value
      #   @linevars = {}
      #   @children = []
      # end

      attr_accessor :file, :line, :method, :object_id, :tp_class, :tp_defined_class, :tp_class_name, :self_type, :depth, :caller, :gem_entry, :children, :parent, :block, :locals, :return_value, :linevars, :node_source, :trace_status, :script, :backtrace_count, :backtrace_location, :script_binding, :script_self

      def initialize(file: nil, line: nil, object_id: nil, method: nil, tp_class: nil, tp_defined_class: nil, tp_class_name: nil, self_type: nil, depth: 0, caller: "", gem_entry: false, parent: nil, block: false, locals: [], return_value: nil, node_source: nil, script: false)
        @file = file
        @line = line
        @method = method
        @object_id = object_id
        @tp_class = tp_class
        @tp_defined_class = tp_defined_class
        @tp_class_name = tp_class_name
        @self_type = self_type
        @children = []
        @depth = depth
        @gem_entry = gem_entry
        @caller = caller
        @parent = parent
        @block = block
        @locals = locals
        @return_value = return_value
        @linevars = Hash.new { |h, k| h[k] = {} }
        @node_source = node_source
        @trace_status = TraceStatus.new(nil)
        @script = script
        @backtrace_count = 0
        @backtrace_location = nil
        @script_binding = nil
        @script_self = nil
      end

      def add_line(lineno, variables)
        @linevars[lineno] = @linevars[lineno].merge(variables)
      end

      def set_args(lineno, variables)
        @linevars[lineno] = @linevars[lineno].merge(variables)
      end

      def inspect
        ivar_inspect = instance_variables.reject { |ivar| [:@children].include?(ivar) }.map do |ivar|
          "#{ivar.to_s}=#{instance_variable_get(ivar).inspect}"
        end
        ivar_inspect << "@children=#<#{@children.map(&:to_s)}>"
        "#<#{self.class.name}:0x#{self.object_id.to_s} #{ivar_inspect.join(', ')}>"
      end

      def inspect_tree(attrs = [], depth = 0)
        str = file.split("/").last + ":#{script ? "script" : method}"
        if !attrs.empty?
          attr_values = attrs.map { |k, v| "#{k}=#{v.inspect}" }.join(', ')
          str += " " + attrs
        end
        str += children.map { |c| "\n" + " " * (depth + 1) * 2 + c.inspect_tree(attrs, depth + 1) }.join()
        return str
      end

      def to_h
        children = depth > Codebeacon::Tracer.config.max_depth ? nil : @children.map(&:to_h)
        is_truncated = depth > Codebeacon::Tracer.config.max_depth ? true : false
        {
          file: @file,
          line: @line,
          method: @method,
          class: @tp_class,
          tp_defined_class: @tp_defined_class,
          tp_class_name: @tp_class_name,
          class_name: @class_name,
          self_type: @self_type,
          gemEntry: @gem_entry,
          caller: @caller,
          isDepthTruncated: is_truncated,
          children: children
        }
      end

      def depth_truncated?
        @depth > Codebeacon::Tracer.config.max_depth && @children.count > 0
      end
    end
  end
end
