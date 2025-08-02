# frozen_string_literal: true

require "thread"
require "fileutils"

module Codebeacon
  module Tracer
    # Manages a background thread to persist trace data asynchronously.
    class AsyncPersistenceManager
      # A simple struct to hold all the data needed for a persistence task.
      PersistenceTask = Struct.new(:metadata, :trees, :node_sources, :config)

      def initialize
        @queue = Queue.new
        @worker_thread = nil
        @logger = Codebeacon::Tracer.logger
      end

      # Starts the background worker thread if it's not already running.
      def start
        return if running?

        @worker_thread = Thread.new do
          # The thread will run until it receives a :shutdown symbol.
          while (task = @queue.pop)
            break if task == :shutdown

            persist_task(task)
          end
        end
      end

      # Stops the background worker thread gracefully.
      def stop
        return unless running?

        # A nil task signals the thread to shut down.
        @queue << :shutdown
        @worker_thread.join # Wait for the thread to finish its current task.
        @worker_thread = nil
      end

      def running?
        @worker_thread&.alive?
      end

      # Adds a new persistence task to the queue.
      def queue_task(metadata:, trees:, node_sources:, config:)
        start unless running? # Ensure the worker is running.
        task = PersistenceTask.new(metadata, trees, node_sources, config)
        @queue << task
      end

      private

      # The actual persistence logic, executed in the background thread.
      def persist_task(task)
        schema = DatabaseSchema.new(task.config)
        schema.create_tables
        DatabaseSchema.trim_db_files(task.config)
        pm = PersistenceManager.new(schema.db)
        pm.save_metadata(task.metadata)
        pm.save_node_sources(task.node_sources)
        pm.save_trees(task.trees)
        schema.create_indexes
        schema.db.close
        touch_refresh(task.config)
      rescue StandardError => e
        @logger.error("AsyncPersistenceManager: Error during persistence: #{e.message}")
        @logger.error(e.backtrace.join("\n")) if task.config.debug?
      end

      # Touches a file to signal that the database has been updated.
      def touch_refresh(config)
        FileUtils.mkdir_p(config.tmp_dir) unless File.exist?(config.tmp_dir)
        if File.exist?(config.refresh_path)
          File.utime(Time.now, Time.now, config.refresh_path)
        else
          File.open(config.refresh_path, "w") {}
        end
      end
    end
  end
end
