# frozen_string_literal: true

require_relative 'type_detector'
require 'timeout'
require 'pp'
require 'stringio'

module Codebeacon
  module Tracer
    class SafeSerializer
      def self.safe_to_s(value, max_length)
        with_safety(max_length) { value.to_s }
      end

      def self.safe_inspect(value, max_length)
        with_safety(max_length) { value.inspect }
      end

      def self.safe_pp(value, max_length)
        with_safety(max_length) do
          io = StringIO.new
          PP.pp(value, io)
          io.string
        end
      end

      def self.with_safety(max_length, &block)
        try_serialize(max_length, &block).first
      end

      def self.try_serialize(max_length)
        return ["...", false] if max_length <= 0

        timeout_ms = Codebeacon::Tracer.config.serialization_timeout_ms
        Timeout.timeout(timeout_ms / 1000.0) do
          result = yield
          return [nil, false] if result.nil?
          result = result.to_s unless result.is_a?(String)
          capped = result.length <= max_length ? result : result[0...max_length] + "..."
          [capped, false]
        end
      rescue Timeout::Error
        ["(serialization timeout)", true]
      rescue StandardError
        [nil, true]
      end

      def self.serialize_all(value, max_length)
        to_s_pair    = try_serialize(max_length) { value.to_s }
        inspect_pair = try_serialize(max_length) { value.inspect }
        pp_pair      = try_serialize(max_length) do
          io = StringIO.new
          PP.pp(value, io)
          io.string
        end

        {
          to_s:    to_s_pair[0],
          inspect: inspect_pair[0],
          pp:      pp_pair[0],
          error:   [to_s_pair, inspect_pair, pp_pair].any? { |(_, err)| err }
        }
      end

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