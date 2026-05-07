# frozen_string_literal: true

require "sqlite3"
require_relative "safe_serializer"

module Codebeacon
  module Tracer
    class CaptureMapper
      def initialize(database)
        @db = database
      end

      def insert(capture, tree_node_id, var_type:)
        max_length = Codebeacon::Tracer.config.max_value_length
        value = capture[1]
        result = SafeSerializer.serialize_all(value, max_length)
        data_type = begin
          value.class.name
        rescue StandardError
          nil
        end
        @db.execute(
          "INSERT INTO captures (name, var_type, data_type, to_s, inspect, pp, error, treenode_id) VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
          [
            capture[0],
            var_type,
            data_type,
            result[:to_s],
            result[:inspect],
            result[:pp],
            result[:error] ? 1 : 0,
            tree_node_id
          ]
        )
      end

      def self.create_table(database)
        database.execute <<-SQL
          CREATE TABLE IF NOT EXISTS captures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            var_type TEXT,
            data_type TEXT,
            to_s TEXT,
            inspect TEXT,
            pp TEXT,
            error INTEGER DEFAULT 0,
            treenode_id INTEGER,
            FOREIGN KEY (treenode_id) REFERENCES treenodes(id)
          );
        SQL
      end

      def self.create_indexes(database)
        database.execute("CREATE INDEX IF NOT EXISTS IDX_captures_treenode_id ON captures(treenode_id)")
      end
    end
  end
end
