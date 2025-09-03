# frozen_string_literal: true

module Codebeacon
  module Tracer
    class BoundaryCallerMapper
      def initialize(database)
        @db = database
        prepare_statement
      end

      def insert(outgoing_method, outgoing_method_as_called)
        @statement.execute(outgoing_method, outgoing_method_as_called)
        @db.last_insert_row_id
      end

      def find_or_create(outgoing_method, outgoing_method_as_called)
        # Try to find existing record
        result = @db.execute(
          "SELECT id FROM boundary_callers WHERE outgoing_method = ? AND outgoing_method_as_called IS ?",
          outgoing_method, outgoing_method_as_called
        ).first

        if result
          result[0] # Return existing ID
        else
          # Create new record and return its ID
          insert(outgoing_method, outgoing_method_as_called)
        end
      end

      def close_statement
        @statement.close if @statement && !@statement.closed?
      end

      def self.create_table(database)
        database.execute <<-SQL
          CREATE TABLE IF NOT EXISTS boundary_callers (
            id INTEGER PRIMARY KEY,
            outgoing_method TEXT,
            outgoing_method_as_called TEXT
          )
        SQL
      end

      def self.create_indexes(database)
        database.execute("CREATE UNIQUE INDEX IF NOT EXISTS IDX_boundary_callers_unique ON boundary_callers(outgoing_method, outgoing_method_as_called)")
        database.execute("CREATE INDEX IF NOT EXISTS IDX_boundary_callers_outgoing_method ON boundary_callers(outgoing_method)")
      end

      private

      def prepare_statement
        sql = <<-SQL
          INSERT INTO boundary_callers
          (
              outgoing_method, outgoing_method_as_called
          )
          VALUES
          (
              ?, ?
          )
        SQL
        @statement = @db.prepare(sql)
      end
    end
  end
end