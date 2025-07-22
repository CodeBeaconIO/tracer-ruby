# frozen_string_literal: true

module Codebeacon
  module Tracer
    class TypeDetector
      BASIC_TYPES = [
        String, Integer, Float, Symbol, TrueClass, FalseClass, NilClass
      ].freeze

      def self.basic_type?(value)
        return true if value.nil?
        BASIC_TYPES.any? { |type| value.is_a?(type) }
      end

      def self.serializable_type?(value)
        basic_type?(value)
      end
    end
  end
end 