require_relative 'call_tree'

module Codebeacon
  module Tracer
    class ThreadLocalCallTreeManager
      attr_reader :trees, :trace_id

      def initialize(trace_id)
        @trees = []
        @trace_id = trace_id
      end

      def current()
        Thread.current[thread_key] ||= begin
          CallTree.new(Thread.current).tap do |tree|
            Codebeacon::Tracer.logger.debug("Creating new call tree for thread: #{Thread.current} with trace_id: #{trace_id}")
            @trees << tree
          end
        end
      end

      def cleanup()
        Thread.list.each do |thread|
          if thread[thread_key]
            thread[thread_key] = nil
          end
        end
      end

      private def thread_key()
        "call_tree_#{trace_id}".to_sym
      end
    end
  end
end
