module Codebeacon
  module Tracer
    class MetadataMapper
      def initialize(database)
        @db = database
      end

      def self.create_table(database)
        database.execute <<-SQL
          CREATE TABLE IF NOT EXISTS metadata (
            id INTEGER PRIMARY KEY,
            name TEXT,
            description TEXT
          );
        SQL
      end

      def self.create_indexes(database)
      end

      def insert(name, description)
        @db.execute("INSERT INTO metadata (name, description) VALUES (?, ?)", [name, description])
      end
    end
  end
end
