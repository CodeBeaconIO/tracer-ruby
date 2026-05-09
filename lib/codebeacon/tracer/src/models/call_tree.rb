# frozen_string_literal: true

module Codebeacon
  module Tracer
    class CallTree
      @thread_id_mutex = Mutex.new
      @thread_id = 0
      
      attr_reader :thread, :root, :current_node, :depth, :call_count, :block_call_count, :synthetic_count

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
        @synthetic_count = 0
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
        @current_node.add_child(new_node)
        @depth += 1
        @current_node = new_node
      end

      def add_return()
        @depth -= 1
        @current_node = @current_node.parent if @current_node
      end

      # Builds a synthetic TreeNode and inserts it between the root and its
      # existing children to absorb a return whose matching call happened before
      # tracing started on this thread. The synthetic node becomes the new sole
      # child of root; existing top-level observed nodes are re-parented under
      # it. current_node stays at root since we just "returned" from the
      # synthetic frame. Returns the synth node for the caller to populate.
      def synthesize_pre_trace_return
        synth = TreeNode.new
        synth.synthetic = true

        existing_children = @root.children
        @root.children = []
        @root.has_children = false
        existing_children.each do |c|
          c.parent = synth
          synth.children << c
        end
        synth.has_children = !existing_children.empty?
        synth.depth = -1 - @synthetic_count
        @root.add_child(synth)
        @synthetic_count += 1
        @current_node = @root
        synth
      end
    end
  end
end
