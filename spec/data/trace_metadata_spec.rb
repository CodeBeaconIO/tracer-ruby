require 'spec_helper'

RSpec.describe Codebeacon::Tracer::TraceMetadata do
  describe '#initialize' do
    it 'initializes with name and description' do
      metadata = Codebeacon::Tracer::TraceMetadata.new(name: "test_trace", description: "test description", trigger_type: "test")
      
      expect(metadata.name).to eq("test_trace")
      expect(metadata.description).to eq("test description")
      expect(metadata.trigger_type).to eq("test")
    end

    it 'captures caller information when provided' do
      caller_location = caller_locations(0, 1).first
      metadata = Codebeacon::Tracer::TraceMetadata.new(name: "caller_test", description: "testing caller capture", caller_location:, trigger_type: "test")
      
      expect(metadata.caller_file).to include('trace_metadata_spec.rb')
      expect(metadata.caller_line).to be > 0
      expect(metadata.caller_method).to be_a(String)
    end

    it 'handles nil caller location gracefully' do
      metadata = Codebeacon::Tracer::TraceMetadata.new(name: "fallback_test", description: "testing fallback", trigger_type: "test")
      
      expect(metadata.caller_file).to be_nil
      expect(metadata.caller_line).to be_nil
      expect(metadata.caller_method).to be_nil
    end

    it 'allows all nil values' do
      metadata = Codebeacon::Tracer::TraceMetadata.new(trigger_type: "test")
      
      expect(metadata.name).to be_nil
      expect(metadata.description).to be_nil
      expect(metadata.trigger_type).to eq("test")
    end
  end

  describe '#finish_trace' do
    it 'calculates duration correctly' do
      metadata = Codebeacon::Tracer::TraceMetadata.new(name: "hash_test", description: "test hash conversion", trigger_type: "test")
      
      # Simulate some processing time
      sleep(0.01)
      
      metadata.finish_trace
      
      expect(metadata.end_time).not_to be_nil
      expect(metadata.duration_ms).to be > 0
    end
  end

  describe '#to_hash' do
    it 'converts to hash with all attributes' do
      metadata = Codebeacon::Tracer::TraceMetadata.new(trigger_type: "test")
      metadata.finish_trace
      
      hash = metadata.to_hash
      
      expect(hash).to include(
        :name, :description, :caller_file, :caller_method, :caller_line,
        :caller_class, :caller_defined_class, :start_time, :end_time,
        :duration_ms, :trigger_type
      )
    end
  end
end 