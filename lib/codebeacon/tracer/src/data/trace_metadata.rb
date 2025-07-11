module Codebeacon
  module Tracer
    class TraceMetadata
      attr_reader :name, :description, :caller_file, :caller_method, :caller_line, 
                  :caller_class, :caller_defined_class, :start_time, 
                  :end_time, :duration_ms, :trigger_type

      def initialize(name: nil, description: nil, caller_location: nil, trigger_type: nil)
        @name = name
        @description = description
        @start_time = Time.now
        @end_time = nil
        @duration_ms = nil
        @trigger_type = trigger_type
        
        if caller_location
          capture_caller_info_from_location(caller_location)
        end
      end

      def finish_trace
        @end_time = Time.now
        @duration_ms = ((@end_time - @start_time) * 1000).round(2)
      end

      def to_hash
        {
          name: @name,
          description: @description,
          caller_file: @caller_file,
          caller_method: @caller_method,
          caller_line: @caller_line,
          caller_class: @caller_class,
          caller_defined_class: @caller_defined_class,
          start_time: @start_time,
          end_time: @end_time,
          duration_ms: @duration_ms,
          trigger_type: @trigger_type
        }
      end

      private

      def capture_caller_info_from_location(location)
        begin
          @caller_file = location.absolute_path || location.path
          @caller_line = location.lineno
          @caller_method = location.label
          
          # Try to determine the calling class/module from the location
          @caller_class, @caller_defined_class = determine_caller_class_from_location(location)
        rescue => e
          Codebeacon::Tracer.logger.warn("Failed to capture caller info from location: #{e.message}") if Codebeacon::Tracer.config.debug?
        end
      end

      def determine_caller_class_from_location(location)
        caller_class = ""
        caller_defined_class = ""

        # Extract class information from the location label if possible
        if location.label && location.label.include?('#')
          # Instance method call - extract class name
          class_method = location.label.split('#')
          caller_class = class_method[0] if class_method.length > 1
        elsif location.label && location.label.include?('.')
          # Class method call - extract class name
          class_method = location.label.split('.')
          caller_class = class_method[0] if class_method.length > 1
        end

        [caller_class, caller_defined_class]
      end
    end
  end
end 