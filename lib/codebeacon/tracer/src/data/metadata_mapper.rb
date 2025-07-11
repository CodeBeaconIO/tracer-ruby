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
            description TEXT,
            caller_file TEXT,
            caller_method TEXT,
            caller_line INTEGER,
            caller_class TEXT,
            caller_defined_class TEXT,
            start_time TEXT,
            end_time TEXT,
            duration_ms REAL,
            trigger_type TEXT
          );
        SQL
      end

      def self.create_indexes(database)
      end

      def insert(metadata)
        metadata_hash = metadata.to_hash
        
        @db.execute(<<-SQL, 
          INSERT INTO metadata (
            name, description, caller_file, caller_method, caller_line,
            caller_class, caller_defined_class, start_time, end_time,
            duration_ms, trigger_type
          ) VALUES (
            ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?
          )
        SQL
          metadata_hash[:name],
          metadata_hash[:description],
          metadata_hash[:caller_file],
          metadata_hash[:caller_method],
          metadata_hash[:caller_line],
          metadata_hash[:caller_class],
          metadata_hash[:caller_defined_class],
          metadata_hash[:start_time]&.iso8601,
          metadata_hash[:end_time]&.iso8601,
          metadata_hash[:duration_ms],
          metadata_hash[:trigger_type]
        )
      end
    end
  end
end
