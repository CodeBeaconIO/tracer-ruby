# frozen_string_literal: true

require 'parser/current'
require_relative "codebeacon/tracer/version"
require 'securerandom'

# Load all the source files
Dir[File.join(File.dirname(__FILE__), 'codebeacon', 'tracer', 'src', '*.rb')].each { |file| require file }
Dir[File.join(File.dirname(__FILE__), 'codebeacon', 'tracer', 'src', 'models', '*.rb')].each { |file| require file }
Dir[File.join(File.dirname(__FILE__), 'codebeacon', 'tracer', 'src', 'data', '*.rb')].each { |file| require file }
Dir[File.join(File.dirname(__FILE__), 'codebeacon', 'tracer', 'src', 'rails', '*.rb')].each { |file| require file } if defined?(Rails::Railtie)

module Codebeacon
  # The Tracer module provides tools to trace and analyze the runtime performance
  # of your Ruby applications. It captures method calls, execution times, and generates
  # reports to help identify bottlenecks.
  #
  # @example Tracing a block of code
  #   Codebeacon::Tracer.trace("My Trace", "Description of what I'm tracing") do |tracer|
  #     # Your code to analyze goes here
  #     some_method_to_analyze
  #   end
  #
  module Tracer
    class << self
      # @return [ThreadLocalCallTreeManager] The current tree manager
      attr_reader :tree_manager

      # Returns the configuration object for Codebeacon::Tracer
      # @return [Configuration] The configuration object
      def config 
        @config ||= Configuration.new
      end

      # Returns the current call tree
      # @return [CallTree] The current call tree
      def current_tree
        @tracer&.tree_manager&.current()
      end

      # Returns the logger instance
      # @return [Logger] The logger instance
      def logger
        config.logger
      end

      # Traces a block of code and collects runtime information
      #
      # @param name [String, nil] Optional name for the trace
      # @param description [String, nil] Optional description for the trace
      # @yield [tracer] Yields the tracer object to the block
      # @yieldparam tracer [Tracer] The tracer object
      # @return [Object] The result of the block
      def trace(name = nil, description = nil)
        unless config.trace_enabled?
          logger.info("Tracing is disabled. Skipping trace: #{name} - #{description}")
          return yield(nil)
        end
        if config.skip_tracing?(name, description)
          logger.info("Exclusion rules matched. Skipping trace: #{name} - #{description}")
          return yield(nil)
        end
        
        begin
          setup
          @tracer = Tracer.new(name, description)
          result = @tracer.enable_traces do
            yield @tracer
          end
          persist(@tracer.name, @tracer.description)
          cleanup
          result
        rescue => e
          Codebeacon::Tracer.logger.error("Error during tracing: #{e.message}")
          Codebeacon::Tracer.logger.error(e.backtrace.join("\n")) if Codebeacon::Tracer.config.debug?
          # Continue execution without crashing the application
          yield nil if block_given?
        end
      end

      # Starts tracing without a block
      # @return [void]
      def start
        return unless config.trace_enabled?
        
        setup
        @tracer = Tracer.new()
        @tracer.start
      end

      # Stops tracing and persists the results
      # @return [void]
      def stop
        return unless @tracer # checks whether trace_enabled? was false when start was called or if it was called

        @tracer.stop
        persist(@tracer.name, @tracer.description)
        cleanup
      end

      private def setup
        Codebeacon::Tracer.config.setup
        @app_node = NodeSource.new('app', Codebeacon::Tracer.config.root_path)
        @gem_node = NodeSource.new('gem', Codebeacon::Tracer.config.gem_path)
        @rubylib_node = NodeSource.new('rubylib', Codebeacon::Tracer.config.rubylib_path)
      end

      private def persist(name = "", description = "")
        if config.skip_tracing?(name, description)
          config.logger.debug("Skipping persistence due to metadata exclusion - name: '#{name}', description: '#{description}'") if config.debug?
          return
        end
        
        if Codebeacon::Tracer.config.dry_run?
          config.logger.debug("Dry run - skipping persistence") if config.debug?
          return
        end

        begin
          schema = DatabaseSchema.new
          schema.create_tables
          DatabaseSchema.trim_db_files
          pm = PersistenceManager.new(schema.db)
          ordered_sources = [ @app_node, @gem_node, @rubylib_node ]
          pm.save_metadata(name, description)
          pm.save_node_sources(ordered_sources)
          pm.save_trees(@tracer.tree_manager.trees)
          schema.create_indexes
          schema.db.close
          touch_refresh
        rescue => e
          Codebeacon::Tracer.logger.error("Error during persistence: #{e.message}")
          Codebeacon::Tracer.logger.error(e.backtrace.join("\n")) if Codebeacon::Tracer.config.debug?
        end
      end

      private def cleanup
        NodeSource.clear
        @tracer.cleanup
      end

      private def touch_refresh
        FileUtils.mkdir_p(Codebeacon::Tracer.config.tmp_dir) unless File.exist?(Codebeacon::Tracer.config.tmp_dir)
        if File.exist?(Codebeacon::Tracer.config.refresh_path)
          File.utime(Time.now, Time.now, Codebeacon::Tracer.config.refresh_path)
        else
          File.open(Codebeacon::Tracer.config.refresh_path, 'w') {}
        end
      end
    end
  end
end
