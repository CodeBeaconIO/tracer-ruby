require 'logger'

module Codebeacon
  module Tracer
    class Logger
      FILENAME = "codebeacon_tracer.log"
      attr_reader :logger

      def initialize(level = nil)
        level ||= Codebeacon::Tracer.config.debug? ? ::Logger::DEBUG : ::Logger::INFO
        @logger ||= ::Logger.new(File.join(Codebeacon::Tracer.config.data_dir, FILENAME), 3, 104857600, level: level)
      end

      def newProgressLogger(*args)
        ProgressLogger.new(@logger, *args)
      end

      def debug(message, *args, &block)
        return unless Codebeacon::Tracer.config.debug?
        @logger.debug(message, *args, &block)
      end

      def method_missing(method, *args, &block)
        if @logger.respond_to?(method)
          @logger.send(method, *args, &block)
        else
          super
        end
      end

      def respond_to_missing?(method, include_private = false)
        @logger.respond_to?(method, include_private) || super
      end
    end

    class ProgressLogger
      PROGRESS_LOG_INTERVAL = 1000

      def initialize(logger, msg, interval = PROGRESS_LOG_INTERVAL)
        @logger = logger
        @msg = msg
        @interval = interval
        @count = 0
      end

      def increment()
        @count += 1
        if @count % @interval == 0
          @logger.info(@count.to_s + " " + @msg)
        end
      end

      def finish()
        @logger.info("Finished: " + @count.to_s + " " + @msg)
      end
    end
  end
end