module Codebeacon
  module Tracer
    class NodeBuilder
      class << self
        def backtrace_location_eql(loc1, loc2)
          loc1.absolute_path == loc2.absolute_path && loc1.lineno == loc2.lineno && loc1.label == loc2.label
        end

        def trace_method_call(call_tree, tp, tp_caller)
          call_tree.add_call
          trace_call(call_tree, tp, tp_caller, :get_method_ast)
        end

        def trace_block_call(call_tree, tp, tp_caller)
          current_context = call_tree.add_block_call
          current_context.block = true
          trace_call(call_tree, tp, tp_caller, :get_block_ast)
        end

        def trace_return(call_tree, tp)
          begin
            current_context = call_tree.current_node
            variable_values = {}
            current_context.return_value = "--Codebeacon::Tracer ERROR-- could not capture return value"
            previous_line = current_context.trace_status.previous_line
            current_context.return_value = tp.return_value
          ensure
            call_tree.add_return()
          end
        end

        private def trace_call(call_tree, tp, tp_caller, ast_get_method)
          current_context = call_tree.current_node

          current_context.file = File.absolute_path(tp.path)
          current_context.node_source = NodeSource.find(tp.path)
          current_context.line = tp.lineno
          current_context.object_id = tp.self.object_id
          current_context.method = tp.method_id
          klass = TPKlass.new(tp)

          current_context.tp_class = klass.tp_class.to_s
          current_context.tp_defined_class = klass.defined_class
          current_context.tp_class_name = klass.tp_class_name
          current_context.self_type = klass.type
          current_context.depth = call_tree.depth

          gem_entry = false
          if Codebeacon::Tracer.config.gem_path \
            && !Codebeacon::Tracer.config.gem_path.empty? \
            && tp.path.start_with?(Codebeacon::Tracer.config.gem_path) # && caller[1].start_with?(Codebeacon::Tracer.config.root_path)
            gem_entry = true
          end
          current_context.gem_entry = gem_entry
          current_context.caller = ""
        end
      end
    end
  end
end
