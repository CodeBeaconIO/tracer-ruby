# frozen_string_literal: true

require_relative "models/node_builder"
require_relative "models/thread_local_call_tree_manager"

module Codebeacon
  module Tracer
    class Tracer
      attr_reader :id, :tree_manager, :metadata, :name, :description

      def initialize(name: nil, description: nil, caller_location: nil, trigger_type: nil)
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("calls traced")
        @total_calls_logger = Codebeacon::Tracer.logger.newProgressLogger("total calls")
        @skip_logger = Codebeacon::Tracer.logger.newProgressLogger("calls skipped")
        @error_call_logger = Codebeacon::Tracer.logger.newProgressLogger("calls errored")
        @error_return_logger = Codebeacon::Tracer.logger.newProgressLogger("returns errored")
        @traces = [trace_call, trace_b_call, trace_return, trace_b_return]
        @name = name
        @description = description
        @trace_id = SecureRandom.uuid
        @tree_manager = ThreadLocalCallTreeManager.new(@trace_id)
        @metadata = TraceMetadata.new(name:, description:, caller_location:, trigger_type:, tracer_version: Codebeacon::Tracer::VERSION)
        @skip_cache = { nil => true } # nil paths are always skipped - caching it here prevents an extra nil check
        @block_caller_stack_walk_limit = Configuration::BLOCK_CALLER_STACK_WALK_LIMIT
      end

      def name=(new_name)
        @name = new_name
        @metadata.instance_variable_set(:@name, new_name)
      end

      def description=(new_description)
        @description = new_description
        @metadata.instance_variable_set(:@description, new_description)
      end

      def id()
        @trace_id
      end

      def call_tree()
        @tree_manager.current()
      end

      def start()
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("calls traced")
        @skip_logger = Codebeacon::Tracer.logger.newProgressLogger("calls skipped", 10000)
        @error_call_logger = Codebeacon::Tracer.logger.newProgressLogger("calls errored", Float::INFINITY)
        @error_return_logger = Codebeacon::Tracer.logger.newProgressLogger("returns errored", Float::INFINITY)
        @total_calls_logger = Codebeacon::Tracer.logger.newProgressLogger("total calls", Float::INFINITY)
        start_traces
      end

      def stop()
        stop_traces
        @progress_logger.finish()
        @skip_logger.finish()
        @error_call_logger.finish()
        @error_return_logger.finish()
        @total_calls_logger.finish()
        @metadata.finish_trace
      end

      def cleanup()
        @tree_manager.cleanup
        NodeBuilder.clear_caches
      end

      def start_traces
        dry_run_log = Codebeacon::Tracer.config.dry_run? ? "--DRY RUN-- " : ""
        Codebeacon::Tracer.logger.info("#{dry_run_log}Starting trace: #{id}")
        @traces.each do |trace|
          trace.enable
        end
      end

      def stop_traces
        @traces.each do |trace|
          trace.disable
        end
        Codebeacon::Tracer.logger.info("END tracing")
      end

      def enable_traces
        start
        return yield
      ensure
        stop
      end

      def trace_call
        trace(:call) do |tp, out_of_bounds|
          current_node = call_tree.current_node
          if out_of_bounds
            track_library_increment(current_node, tp)
            @skip_logger.increment()
            next
          end
          if current_node.library_depth > 0 && current_node.library_exit_info
            NodeBuilder.trace_method_call_with_callback(call_tree, tp, "", current_node.library_exit_info)
          else
            NodeBuilder.trace_method_call(call_tree, tp, "")
          end

          @progress_logger.increment()
        ensure
          @total_calls_logger.increment()
        end
      end

      def trace_b_call
        # The following magic number gets us the caller method of the current block.
        #   The first two callers are blocks within this tracer.
        #   The next caller is actually the block itself (I don't know why - I'm surprised this is already on the stack)
        #   The 4th caller (0 index: 3) is the calling method at least in the case of C calls.
        block_caller_depth = 3
        trace(:b_call) do |tp, out_of_bounds|
          first_caller = nil
          if !tp.method_id.nil?
            # Check the immediate caller first
            immediate_loc = caller_locations(block_caller_depth, 1).first
            if immediate_loc
              immediate_path = immediate_loc.absolute_path || immediate_loc.path
              immediate_is_skipped = @skip_cache.key?(immediate_path) ? @skip_cache[immediate_path] : skip_methods?(immediate_path)

              if immediate_is_skipped
                # Immediate caller is library code - walk back to find the boundary
                depth = block_caller_depth
                max_depth = block_caller_depth + @block_caller_stack_walk_limit
                last_skipped_caller = nil
                found_boundary = false

                while depth < max_depth
                  loc = caller_locations(depth, 1).first
                  break unless loc  # End of stack reached

                  # Check if this caller's path is skipped
                  path = loc.absolute_path || loc.path
                  is_skipped = @skip_cache.key?(path) ? @skip_cache[path] : skip_methods?(path)

                  if is_skipped
                    # Keep track of this skipped caller - it might be the boundary
                    last_skipped_caller = loc
                    depth += 1
                  else
                    # Hit non-skipped code - we found the boundary!
                    found_boundary = true
                    break
                  end
                end

                # Only use last_skipped_caller if we found a proper boundary
                # If we hit max_depth without finding boundary, first_caller stays nil
                first_caller = last_skipped_caller if found_boundary
              else
                # Immediate caller is app code - use it directly
                first_caller = immediate_loc
              end
            end
          end
          current_node = call_tree.current_node
          if out_of_bounds
            track_library_increment(current_node, tp)
            @skip_logger.increment()
            next
          end

          if current_node.library_depth > 0 && current_node.library_exit_info
            node = NodeBuilder.trace_block_call_with_callback(call_tree, tp, "", current_node.library_exit_info)
            node.caller = first_caller&.label
          else
            node = NodeBuilder.trace_block_call(call_tree, tp, "")
            node.caller = first_caller&.label
          end

          @progress_logger.increment()
        ensure
          @total_calls_logger.increment()
        end
      end

      def trace_return
        trace(:return) do |tp, out_of_bounds|
          if out_of_bounds
            track_library_decrement(call_tree.current_node, tp.path)
          else
            NodeBuilder.trace_return(call_tree, tp)
          end
        end
      end

      def trace_b_return
        trace(:b_return) do |tp, out_of_bounds|
          if out_of_bounds
            track_library_decrement(call_tree.current_node, tp.path)
          else
            NodeBuilder.trace_return(call_tree, tp)
          end
        end
      end

      def trace(type)
        TracePoint.new(type) do |tp|
          path = tp.path
          yield tp, (@skip_cache.key?(path) ? @skip_cache[path] : skip_methods?(path))
        rescue => e
          Codebeacon::Tracer.logger.error("TracePoint(#{type}) #{tp.path} #{e.message}")
          if type == :call || type == :b_call
            @error_call_logger.increment()
          elsif type == :return || type == :b_return
            @error_return_logger.increment()
          end
        end
      end

      def track_library_increment(current_node, tp)
        return if current_node.is_root?

        if current_node.library_depth == 0
          current_node.library_exit_info = {
            outgoing_method: tp.method_id.to_s,
            outgoing_method_as_called: tp.callee_id != tp.method_id ? tp.callee_id.to_s : nil
          }
        end
        current_node.library_depth += 1
      end

      def track_library_decrement(current_node, path)
        return if current_node.is_root?

        if current_node.library_depth > 0
          current_node.library_depth -= 1
          if current_node.library_depth == 0
            current_node.library_exit_info = nil
          end
        end
      end

      def skip_methods?(path)
        # Note: path.nil? and cache checks are now inlined in trace() for performance

        # Check if the path is in the exclude list.
        # We need to check "relative" paths first because we need to exclude the special "<internal..." style paths.
        # If we try to find the absolute path, it will prepend the root/cwd and will end up being traced
        is_excluded = Codebeacon::Tracer.config.exclude_paths.any? do |exclude_path|
          path.start_with?(exclude_path)
        end
        return @skip_cache[path] = true if is_excluded

        # Check if the absolute path is in the exclude list.
        # This is required when the traced program is run using a relative path
        abs_path = File.absolute_path(path)
        is_excluded = Codebeacon::Tracer.config.exclude_paths.any? do |exclude_path|
          abs_path.start_with?(exclude_path)
        end
        return @skip_cache[path] = true if is_excluded

        # Check if we are only tracing local methods and if the path is outside the project's root.
        is_local_only = Codebeacon::Tracer.config.local_methods_only?
        is_not_in_root = !abs_path.start_with?(Codebeacon::Tracer.config.root_path)
        return @skip_cache[path] = true if is_local_only && is_not_in_root

        @skip_cache[path] = false
      end
    end
  end
end
