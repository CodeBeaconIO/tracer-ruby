# frozen_string_literal: true

require_relative "models/node_builder"
require_relative "models/thread_local_call_tree_manager"

module Codebeacon
  module Tracer
    class Tracer
      attr_reader :id, :tree_manager, :metadata, :name, :description

      def initialize(name: nil, description: nil, caller_location: nil, trigger_type: nil)
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("calls traced")
        @skip_logger = Codebeacon::Tracer.logger.newProgressLogger("calls skipped")
        @traces = [trace_call, trace_b_call, trace_return, trace_b_return]
        @name = name
        @description = description
        @trace_id = SecureRandom.uuid
        @tree_manager = ThreadLocalCallTreeManager.new(@trace_id)
        @metadata = TraceMetadata.new(name:, description:, caller_location:, trigger_type:)
        @skip_cache = {}
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
        start_traces
      end

      def stop()
        stop_traces
        @progress_logger.finish()
        @skip_logger.finish()
        @metadata.finish_trace
      end

      def cleanup()
        @tree_manager.cleanup
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
        trace(:call) do |tp|
          NodeBuilder.trace_method_call(call_tree, tp, "")
        ensure
          @progress_logger.increment()
        end
      end

      def trace_b_call
        trace(:b_call) do |tp|
          NodeBuilder.trace_block_call(call_tree, tp, "")
        ensure
          @progress_logger.increment()
        end
      end

      def trace_return
        trace(:return) do |tp|
          NodeBuilder.trace_return(call_tree, tp)
        end
      end

      def trace_b_return
        trace(:b_return) do |tp|
          NodeBuilder.trace_return(call_tree, tp)
        end
      end

      def trace(type)
        TracePoint.new(type) do |tp|
          if skip_methods?(tp.path)
            @skip_logger.increment()
            next
          end
          yield tp
        rescue => e
          Codebeacon::Tracer.logger.error("TracePoint(#{type}) #{tp.path} #{e.message}")
        end
      end

      def skip_methods?(path)
        return true if path.nil?
        
        return @skip_cache[path] if @skip_cache.key?(path)

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
