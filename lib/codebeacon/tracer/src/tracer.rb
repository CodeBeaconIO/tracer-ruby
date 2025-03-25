require_relative 'models/node_builder'
require_relative 'models/thread_local_call_tree_manager'

module Codebeacon
  module Tracer
    class Tracer
      attr_reader :id, :tree_manager
      attr_accessor :name, :description

      def initialize(name = nil, description = nil)
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("calls traced")
        @traces = [trace_call, trace_b_call, trace_return, trace_b_return]
        @name = name
        @description = description
        @trace_id = SecureRandom.uuid
        @tree_manager = ThreadLocalCallTreeManager.new(@trace_id)
      end

      def id()
        @trace_id
      end

      def call_tree()
        @tree_manager.current()
      end

      def start()
        @progress_logger = Codebeacon::Tracer.logger.newProgressLogger("calls traced")
        start_traces
      end

      def stop()
        stop_traces
        @progress_logger.finish()
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
          NodeBuilder.trace_method_call(call_tree, tp, Kernel.caller[2..])
        ensure
          @progress_logger.increment()
        end
      end

      def trace_b_call
        trace(:b_call) do |tp|
          NodeBuilder.trace_block_call(call_tree, tp, Kernel.caller[2..])
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
          paths = [tp.path]
          # capture calls and returns to skipped paths from non skipped paths. All I need is the return value to display in recorded files, but the code doesn't yet support this without tracing the entire call and return.
          if [:call, :b_call, :return, :b_return].include?(type)
            paths << Kernel.caller(1..1)[0]
          end
          next if skip_methods?(paths)
          yield tp
        rescue => e
          Codebeacon::Tracer.logger.error("TracePoint(#{type}) #{tp.path} #{e.message}")
        end
      end

      def skip_methods?(paths)
        paths.all? do |path|
          path.nil? || Codebeacon::Tracer.config.exclude_paths.any?{ |exclude_path| path.start_with?(exclude_path) } ||
            Codebeacon::Tracer.config.local_methods_only? && !path.start_with?(Codebeacon::Tracer.config.root_path)
        end
      end
    end
  end
end
