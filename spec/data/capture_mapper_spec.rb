require 'spec_helper'
require 'sqlite3'

RSpec.describe Codebeacon::Tracer::CaptureMapper do
  before(:all) do
    @db = SQLite3::Database.new ":memory:"
    Codebeacon::Tracer::CaptureMapper.create_table(@db)
    Codebeacon::Tracer::CaptureMapper.create_indexes(@db)
  end

  before(:each) do
    @db.execute("DELETE FROM captures")
    @mapper = Codebeacon::Tracer::CaptureMapper.new(@db)
  end

  describe '#insert' do
    it 'populates all serialization columns for a primitive arg' do
      @mapper.insert(["count", 42], 7, var_type: "arg")

      row = @db.execute("SELECT name, var_type, data_type, to_s, inspect, pp, error, treenode_id FROM captures").first
      expect(row[0]).to eq("count")
      expect(row[1]).to eq("arg")
      expect(row[2]).to eq("Integer")
      expect(row[3]).to eq("42")
      expect(row[4]).to eq("42")
      expect(row[5]).to include("42")
      expect(row[6]).to eq(0)
      expect(row[7]).to eq(7)
    end

    it 'inserts a return capture with NULL name' do
      @mapper.insert([nil, "result"], 11, var_type: "return")

      row = @db.execute("SELECT name, var_type, data_type, inspect FROM captures").first
      expect(row[0]).to be_nil
      expect(row[1]).to eq("return")
      expect(row[2]).to eq("String")
      expect(row[3]).to eq('"result"')
    end

    it 'sets error=1 when a serializer raises' do
      raising = Class.new do
        def to_s; raise "boom"; end
        def inspect; raise "boom"; end
      end.new
      @mapper.insert(["bad", raising], 9, var_type: "arg")

      error_flag = @db.execute("SELECT error FROM captures").first.first
      expect(error_flag).to eq(1)
    end

    it 'inspect quotes strings while to_s does not' do
      @mapper.insert(["greeting", "hello"], 3, var_type: "arg")

      row = @db.execute("SELECT to_s, inspect FROM captures").first
      expect(row[0]).to eq("hello")
      expect(row[1]).to eq('"hello"')
    end

    it 'serializes hashes across all formats' do
      @mapper.insert(["data", { a: 1 }], 1, var_type: "arg")

      row = @db.execute("SELECT to_s, inspect, pp FROM captures").first
      expect(row[0]).to eq("{:a=>1}")
      expect(row[1]).to eq("{:a=>1}")
      expect(row[2]).to include(":a=>1")
    end

    it 'records data_type for nil' do
      @mapper.insert([nil, nil], 4, var_type: "return")

      row = @db.execute("SELECT data_type FROM captures").first
      expect(row[0]).to eq("NilClass")
    end
  end

  describe '.create_table' do
    it 'creates the captures table with expected columns' do
      db = SQLite3::Database.new ":memory:"
      Codebeacon::Tracer::CaptureMapper.create_table(db)

      columns = db.execute("PRAGMA table_info(captures)").map { |row| row[1] }
      expect(columns).to include("id", "name", "var_type", "data_type", "to_s", "inspect", "pp", "error", "treenode_id")
    end
  end

  describe '.create_indexes' do
    it 'creates IDX_captures_treenode_id' do
      db = SQLite3::Database.new ":memory:"
      Codebeacon::Tracer::CaptureMapper.create_table(db)
      Codebeacon::Tracer::CaptureMapper.create_indexes(db)

      indexes = db.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='captures'").map { |row| row[0] }
      expect(indexes).to include("IDX_captures_treenode_id")
    end
  end
end
