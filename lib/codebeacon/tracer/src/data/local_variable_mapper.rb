# frozen_string_literal: true

require "sqlite3"
require_relative "safe_serializer"

module Codebeacon
  module Tracer
    class LocalVariableMapper
      def initialize(database)
        @db = database
      end

      def insert(local, tree_node_id)
        max_length = Codebeacon::Tracer.config.max_value_length
        result = SafeSerializer.serialize_all(local[1], max_length)
        @db.execute(
          "INSERT INTO locals (name, to_s, inspect, pp, error, treenode_id) VALUES (?, ?, ?, ?, ?, ?)",
          [
            local[0],
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
          CREATE TABLE IF NOT EXISTS locals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
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
        database.execute("CREATE INDEX IF NOT EXISTS IDX_locals_treenode_id ON locals(treenode_id)")
      end
    end
  end
end
