module Codebeacon
  module Tracer
    class CallTree
      @thread_id_mutex = Mutex.new
      @thread_id = 0
      
      attr_reader :thread, :root, :current_node, :depth, :call_count, :block_call_count

      def self.next_thread_id
        @thread_id_mutex.synchronize do
          @thread_id += 1
        end
      end

      def initialize(thread)
        @thread = thread
        root_name = (thread.name || "thread") + " (#{CallTree.next_thread_id})"
        @root = TreeNode.new(method: root_name)
        @root.file, @root.line = __FILE__, __LINE__
        @current_node = @root
        @depth = 0
        @call_count = 0
        @block_call_count = 0
      end

      def total_call_count
        @call_count + @block_call_count
      end

      def add_call()
        @call_count += 1
        add_node()
      end

      def add_block_call()
        @block_call_count += 1
        add_node()
      end

      def add_node()
        new_node = TreeNode.new()
        @current_node.children << new_node
        new_node.parent = @current_node
        @depth += 1
        @current_node = new_node
      end

      def add_return()
        @depth -= 1
        @current_node = @current_node.parent if @current_node
      end
    end
  end
end