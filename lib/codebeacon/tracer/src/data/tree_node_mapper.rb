# frozen_string_literal: true

require "sqlite3"
require "json"

module Codebeacon
  module Tracer
    class TreeNodeMapper
      def initialize(database)
        @db = database
        prepare_statement
      end

      def insert(file, line, called_method, method, tp_class, tp_defined_class, tp_class_name, self_type, depth, caller, gem_entry, parent_id, block, node_source_id, return_type, return_value)
        @statement.execute(file, line, called_method, method, tp_class, tp_defined_class, tp_class_name, self_type, depth, caller, gem_entry ? 1 : 0, parent_id, block ? 1 : 0, node_source_id, return_type, return_value)
        @db.last_insert_row_id
      end

      def close_statement
        @statement.close if @statement && !@statement.closed?
      end

      def self.create_table(database)
        database.execute <<-SQL
          CREATE TABLE IF NOT EXISTS treenodes (
            id INTEGER PRIMARY KEY,
            file TEXT,
            line INTEGER,
            called_method TEXT,
            method TEXT,
            tp_class TEXT,
            tp_defined_class TEXT,
            tp_class_name TEXT,
            self_type TEXT,
            depth INTEGER,
            caller TEXT,
            gemEntry INTEGER,
            parent_id INTEGER,
            block INTEGER,
            node_source_id INTEGER,
            return_type TEXT,
            return_value TEXT,
            FOREIGN KEY (parent_id) REFERENCES treenodes(id),
            FOREIGN KEY (node_source_id) REFERENCES node_sources(id)
          )
        SQL
      end

      def self.create_indexes(database)
        database.execute("CREATE INDEX IF NOT EXISTS IDX_treenode_parent_id ON treenodes(parent_id)")
        database.execute("CREATE INDEX IF NOT EXISTS IDX_treenode_node_source_id ON treenodes(node_source_id)")
        database.execute("CREATE INDEX IF NOT EXISTS IDX_treenode_file ON treenodes(file)")
        database.execute("CREATE INDEX IF NOT EXISTS IDX_treenode_called_method ON treenodes(called_method)")
      end

      private

      def prepare_statement
        sql = <<-SQL
          INSERT INTO treenodes
          (
              file, line, called_method, method, tp_class, tp_defined_class, tp_class_name, self_type, depth, caller,
              gemEntry, parent_id, block, node_source_id, return_type, return_value
          )
          VALUES
          (
              ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
          )
        SQL
        @statement = @db.prepare(sql)
      end
    end
  end
end
