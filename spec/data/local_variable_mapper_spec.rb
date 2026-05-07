require 'spec_helper'
require 'sqlite3'

RSpec.describe Codebeacon::Tracer::LocalVariableMapper do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    Codebeacon::Tracer::LocalVariableMapper.create_table(@db)
    Codebeacon::Tracer::LocalVariableMapper.create_indexes(@db)
  end

  before(:each) do
    @db.execute("DELETE FROM locals")
    @mapper = Codebeacon::Tracer::LocalVariableMapper.new(@db)
  end

  describe '#insert' do
    it 'populates all serialization columns for a primitive' do
      @mapper.insert(["count", 42], 7)

      row = @db.execute("SELECT name, to_s, inspect, pp, error, treenode_id FROM locals").first
      expect(row[0]).to eq("count")
      expect(row[1]).to eq("42")
      expect(row[2]).to eq("42")
      expect(row[3]).to include("42")
      expect(row[4]).to eq(0)
      expect(row[5]).to eq(7)
    end

    it 'sets error=1 when a serializer raises' do
      raising = Class.new do
        def to_s; raise "boom"; end
        def inspect; raise "boom"; end
      end.new
      @mapper.insert(["bad", raising], 9)

      error_flag = @db.execute("SELECT error FROM locals").first.first
      expect(error_flag).to eq(1)
    end

    it 'inspect quotes strings while to_s does not' do
      @mapper.insert(["greeting", "hello"], 3)

      row = @db.execute("SELECT to_s, inspect FROM locals").first
      expect(row[0]).to eq("hello")
      expect(row[1]).to eq('"hello"')
    end

    it 'serializes hashes across all formats' do
      @mapper.insert(["data", { a: 1 }], 1)

      row = @db.execute("SELECT to_s, inspect, pp FROM locals").first
      expect(row[0]).to eq("{:a=>1}")
      expect(row[1]).to eq("{:a=>1}")
      expect(row[2]).to include(":a=>1")
    end
  end

  describe '.create_table' do
    it 'creates the locals table with expected columns' do
      db = SQLite3::Database.new ":memory:"
      Codebeacon::Tracer::LocalVariableMapper.create_table(db)

      columns = db.execute("PRAGMA table_info(locals)").map { |row| row[1] }
      expect(columns).to include("id", "name", "to_s", "inspect", "pp", "error", "treenode_id")
      expect(columns).not_to include("value", "json", "yaml")
    end
  end

  describe '.create_indexes' do
    it 'creates IDX_locals_treenode_id' do
      db = SQLite3::Database.new ":memory:"
      Codebeacon::Tracer::LocalVariableMapper.create_table(db)
      Codebeacon::Tracer::LocalVariableMapper.create_indexes(db)

      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='locals'").map { |row| row[0] }
      expect(indexes).to include("IDX_locals_treenode_id")
    end
  end
end
