require_relative '../models/node_source'

module Codebeacon
  module Tracer
    class NodeSourceMapper
      def initialize(database)
        @db = database
      end

      def self.create_table(database)
        database.execute <<-SQL
          CREATE TABLE IF NOT EXISTS node_sources (
            id INTEGER PRIMARY KEY,
            name TEXT NOT NULL,
            root_path TEXT NOT NULL
          );
        SQL
      end

      def self.create_indexes(database)
      end

      def insert(name, root_path)
        @db.execute("INSERT INTO node_sources (name, root_path) VALUES (?, CAST(? AS TEXT))", [name, root_path])
        @db.last_insert_row_id
      end
    end
  end
end
