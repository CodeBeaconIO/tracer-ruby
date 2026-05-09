module Codebeacon
  module Tracer
    class NodeBuilder
      class << self
        attr_accessor :absolute_path_cache, :node_source_cache

        def initialize_caches
          @absolute_path_cache ||= {}
          @node_source_cache ||= {}
        end

        def clear_caches
          @absolute_path_cache&.clear
          @node_source_cache&.clear
          TPKlass.clear_cache
        end

        def backtrace_location_eql(loc1, loc2)
          loc1.absolute_path == loc2.absolute_path && loc1.lineno == loc2.lineno && loc1.label == loc2.label
        end

        def trace_method_call(call_tree, tp, tp_caller)
          initialize_caches
          call_tree.add_call
          trace_call(call_tree, tp, tp_caller, :get_method_ast)
        end

        def trace_block_call(call_tree, tp, tp_caller)
          initialize_caches
          current_context = call_tree.add_block_call
          current_context.block = true
          trace_call(call_tree, tp, tp_caller, :get_block_ast)
        end

        def trace_method_call_with_callback(call_tree, tp, tp_caller, library_exit_info)
          initialize_caches
          parent_library_depth = call_tree.current_node.library_depth
          call_tree.add_call
          new_node = trace_call(call_tree, tp, tp_caller, :get_method_ast)
          
          # Keep track of current library depth as we may have additional nested calls that we trace.
          new_node.library_depth = parent_library_depth
          new_node.callback_info = {
            outgoing_method: library_exit_info[:outgoing_method].to_s,
            outgoing_method_as_called: library_exit_info[:outgoing_method_as_called]
          }
          
          new_node
        end

        def trace_block_call_with_callback(call_tree, tp, tp_caller, library_exit_info)
          initialize_caches
          parent_library_depth = call_tree.current_node.library_depth
          current_context = call_tree.add_block_call
          current_context.block = true
          new_node = trace_call(call_tree, tp, tp_caller, :get_block_ast)
          
          # Keep track of current library depth as we may have additional nested calls that we trace.
          new_node.library_depth = parent_library_depth
          new_node.callback_info = {
            outgoing_method: library_exit_info[:outgoing_method].to_s,
            outgoing_method_as_called: library_exit_info[:outgoing_method_as_called]
          }
          
          new_node
        end

        def trace_return(call_tree, tp)
          current_context = call_tree.current_node
          if current_context.is_root?
            initialize_caches
            synth = call_tree.synthesize_pre_trace_return
            populate_synth(synth, tp, block: tp.event == :b_return)
          else
            begin
              current_context.return_value = "--Codebeacon::Tracer ERROR-- could not capture return value"
              previous_line = current_context.trace_status.previous_line
              current_context.return_value = tp.return_value
              record_locals(current_context, tp)
            ensure
              call_tree.add_return()
            end
          end
        end

        private def trace_call(call_tree, tp, tp_caller, ast_get_method)
          current_context = call_tree.current_node

          # Cache absolute path resolution
          current_context.file = @absolute_path_cache[tp.path] ||= File.absolute_path(tp.path)
          
          # Cache NodeSource lookup (properly cache nil results)
          if @node_source_cache.key?(tp.path)
            current_context.node_source = @node_source_cache[tp.path]
          else
            current_context.node_source = @node_source_cache[tp.path] = NodeSource.find(tp.path)
          end
          current_context.line = tp.lineno
          current_context.object_id = tp.self.object_id
          current_context.method = tp.method_id
          if tp.callee_id != tp.method_id
            current_context.called_method = tp.callee_id
          end

          klass = TPKlass.for_tp(tp)
          current_context.tp_class = klass.tp_class.to_s
          current_context.tp_defined_class = klass.defined_class
          current_context.tp_class_name = klass.tp_class_name.to_s
          current_context.self_type = klass.type
          current_context.depth = call_tree.depth

          record_args(current_context, tp)

          gem_entry = false
          if Codebeacon::Tracer.config.gem_path \
            && !Codebeacon::Tracer.config.gem_path.empty? \
            && tp.path.start_with?(Codebeacon::Tracer.config.gem_path) # && caller[1].start_with?(Codebeacon::Tracer.config.root_path)
            gem_entry = true
          end
          current_context.gem_entry = gem_entry
          current_context.caller = ""
          
          current_context
        end

        
        # Back-populates a synthetic TreeNode (created by CallTree.synthesize_pre_trace_return)
        # for a return whose matching call wasn't observed — e.g. a thread that was
        # mid-stack when tracing armed. Captures whatever the return-time TracePoint
        # exposes: identity, defined_class, return_value, args and locals via binding.
        # file/line refer to the return site, which differs from observed nodes whose
        # line is the call site.
        # Theoretically, this shouldn't be called often. Performance isn't is critical,
        # so we can afford this method call. If it is called often, we *probably* have
        # an error or at least it should be a rare edge case.
        private def populate_synth(node, tp, block:)
          node.block = block
          node.file = @absolute_path_cache[tp.path] ||= File.absolute_path(tp.path)
          if @node_source_cache.key?(tp.path)
            node.node_source = @node_source_cache[tp.path]
          else
            node.node_source = @node_source_cache[tp.path] = NodeSource.find(tp.path)
          end
          node.line = tp.lineno
          node.object_id = tp.self.object_id
          node.method = tp.method_id
          node.called_method = tp.callee_id if tp.callee_id != tp.method_id

          klass = TPKlass.for_tp(tp)
          node.tp_class = klass.tp_class.to_s
          node.tp_defined_class = klass.defined_class
          node.tp_class_name = klass.tp_class_name.to_s
          node.self_type = klass.type

          gem_path = Codebeacon::Tracer.config.gem_path
          node.gem_entry = !!(gem_path && !gem_path.empty? && tp.path.start_with?(gem_path))
          node.caller = ""
          
          node
        end

        private def record_args(current_context, tp)
          parameters = tp.parameters
          return current_context.args = [] if parameters.empty?

          binding_obj = tp.binding
          current_context.args = parameters.filter_map do |(_kind, name)|
            next if name.nil?

            begin
              [name.to_s, binding_obj.local_variable_get(name)]
            rescue StandardError
              nil
            end
          end
        rescue StandardError
          current_context.args = []
        end

        private def record_locals(current_context, tp)
          binding_obj = tp.binding
          return current_context.locals = [] if binding_obj.nil?

          arg_names = current_context.args.map { |(name, _)| name }
          current_context.locals = binding_obj.local_variables.filter_map do |name|
            next if arg_names.include?(name.to_s)

            begin
              [name.to_s, binding_obj.local_variable_get(name)]
            rescue StandardError
              nil
            end
          end
        rescue StandardError
          current_context.locals = []
        end
      end
    end
  end
end
