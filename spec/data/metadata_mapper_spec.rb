require 'spec_helper'

RSpec.describe Codebeacon::Tracer::MetadataMapper do
  before(:each) do
    @db = SQLite3::Database.new(":memory:")
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    @mapper = Codebeacon::Tracer::MetadataMapper.new(@db)
  end

  describe '#insert' do
    it 'inserts metadata into the database' do
      metadata = Codebeacon::Tracer::TraceMetadata.new(
        name: "test_trace",
        description: "test description",
        trigger_type: "test"
      )
      metadata.finish_trace

      @mapper.insert(metadata)

      result = @db.execute("SELECT * FROM metadata WHERE name = ?", "test_trace").first
      expect(result).not_to be_nil
      expect(result[1]).to eq("test_trace") # name
      expect(result[2]).to eq("test description") # description
      expect(result[11]).to eq("test") # trigger_type
      expect(result[12]).to eq("ruby") # language
    end

    it 'inserts metadata with caller information' do
      caller_location = caller_locations(0, 1).first
      metadata = Codebeacon::Tracer::TraceMetadata.new(
        name: "caller_test",
        description: "testing caller capture",
        caller_location: caller_location,
        trigger_type: "test"
      )
      metadata.finish_trace

      @mapper.insert(metadata)

      result = @db.execute("SELECT * FROM metadata WHERE name = ?", "caller_test").first
      expect(result[3]).to include('metadata_mapper_spec.rb') # caller_file
      expect(result[4]).to be_a(String) # caller_method
      expect(result[5]).to be > 0 # caller_line
      expect(result[12]).to eq("ruby") # language
    end
  end

  describe '.create_table' do
    it 'creates the metadata table' do
      result = @db.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='metadata'")
      expect(result).not_to be_empty
    end

    it 'creates the table with the correct columns' do
      result = @db.execute("PRAGMA table_info(metadata)")
      column_names = result.map { |col| col[1] }
      
      expected_columns = [
        "id", "name", "description", "caller_file", "caller_method", "caller_line",
        "caller_class", "caller_defined_class", "start_time", "end_time",
        "duration_ms", "trigger_type", "language"
      ]
      
      expected_columns.each do |column|
        expect(column_names).to include(column)
      end
    end
  end

  describe '.create_indexes' do
    it 'creates no indexes (as currently implemented)' do
      # The current implementation has no indexes, so we just verify the method exists
      expect { Codebeacon::Tracer::MetadataMapper.create_indexes(@db) }.not_to raise_error
    end
  end
end 