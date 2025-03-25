require 'sqlite3'
require 'fileutils'
require_relative 'tree_node_mapper'
require_relative 'node_source_mapper'

module Codebeacon
  module Tracer
    class DatabaseSchema
      def initialize
        @db = initialize_db
      end

      def db
        @db
      end

      def initialize_db
        db_path = Codebeacon::Tracer.config.db_path
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        db_name = "#{Codebeacon::Tracer.config.db_name}_#{timestamp}.db"
        db_symlink = File.join(db_path, "#{Codebeacon::Tracer.config.db_name}.db")

        File.delete(db_symlink) if File.exist?(db_symlink)
        FileUtils.ln_sf(db_name, db_symlink)
        SQLite3::Database.new(File.join(db_path, db_name))
      end

      def create_tables
        MetadataMapper.create_table(db)
        TreeNodeMapper.create_table(db)
        NodeSourceMapper.create_table(db)
      end

      def create_indexes
        MetadataMapper.create_indexes(db)
        TreeNodeMapper.create_indexes(db)
        NodeSourceMapper.create_indexes(db)
      end

      def self.trim_db_files
        db_path = Codebeacon::Tracer.config.db_path
        db_files = Dir.glob(File.join(db_path, "*.db"))
        db_files.reject! { |file| File.symlink?(file) }
        db_files.sort_by! { |db_file| File.mtime(db_file) }
        db_files.reverse!

        db_files.each_with_index do |db_file, index|
          next if index < Codebeacon::Tracer.config.max_db_files
          File.delete(db_file)
        end
      end
    end
  end
end
