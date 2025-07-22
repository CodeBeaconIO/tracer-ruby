require 'spec_helper'

RSpec.describe "Language field integration" do
  before(:each) do
    @db = SQLite3::Database.new(":memory:")
    Codebeacon::Tracer::MetadataMapper.create_table(@db)
    Codebeacon::Tracer::TreeNodeMapper.create_table(@db)
    Codebeacon::Tracer::NodeSourceMapper.create_table(@db)
    @persistence_manager = Codebeacon::Tracer::PersistenceManager.new(@db)
  end

  it "persists language field as 'ruby' when saving metadata" do
    metadata = Codebeacon::Tracer::TraceMetadata.new(
      name: "integration_test",
      description: "testing language field persistence",
      trigger_type: "integration"
    )
    metadata.finish_trace

    @persistence_manager.save_metadata(metadata)

    result = @db.execute("SELECT language FROM metadata WHERE name = ?", "integration_test").first
    expect(result[0]).to eq("ruby")
  end

  it "persists language field in complete tracer workflow" do
    # Simulate a complete tracing session
    metadata = Codebeacon::Tracer::TraceMetadata.new(
      name: "complete_workflow_test",
      description: "testing complete workflow with language field",
      trigger_type: "workflow"
    )

    # Simulate some tracing activity
    sleep(0.01)
    metadata.finish_trace

    # Save through persistence manager
    @persistence_manager.save_metadata(metadata)

    # Verify the language field is persisted correctly
    result = @db.execute("SELECT name, description, language FROM metadata WHERE name = ?", "complete_workflow_test").first
    expect(result[0]).to eq("complete_workflow_test")
    expect(result[1]).to eq("testing complete workflow with language field")
    expect(result[2]).to eq("ruby")
  end

  it "ensures all metadata records have language field set to 'ruby'" do
    # Create multiple metadata records
    metadata1 = Codebeacon::Tracer::TraceMetadata.new(name: "test1", trigger_type: "test")
    metadata2 = Codebeacon::Tracer::TraceMetadata.new(name: "test2", trigger_type: "test")
    metadata3 = Codebeacon::Tracer::TraceMetadata.new(name: "test3", trigger_type: "test")

    [metadata1, metadata2, metadata3].each(&:finish_trace)

    # Save all metadata
    [metadata1, metadata2, metadata3].each { |m| @persistence_manager.save_metadata(m) }

    # Verify all records have language set to 'ruby'
    results = @db.execute("SELECT language FROM metadata")
    expect(results.length).to eq(3)
    results.each do |result|
      expect(result[0]).to eq("ruby")
    end
  end
end 