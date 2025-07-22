# frozen_string_literal: true

require_relative 'type_detector'
require 'timeout'

module Codebeacon
  module Tracer
    class SafeSerializer
      def self.serialize(value, max_length)
        return nil unless TypeDetector.serializable_type?(value)
        return "..." if max_length <= 0
        
        timeout_ms = Codebeacon::Tracer.config.serialization_timeout_ms
        
        begin
          Timeout.timeout(timeout_ms / 1000.0) do
            serialized = case value
            when String
              value
            when Integer, Float
              value.to_s
            when Symbol, TrueClass, FalseClass
              value.to_s
            when NilClass
              "nil"
            else
              nil
            end

            return nil if serialized.nil?

            serialized.length <= max_length ? serialized : serialized[0...max_length] + "..."
          end
        rescue Timeout::Error
          return "(serialization timeout)"
        end
      end
    end
  end
end 