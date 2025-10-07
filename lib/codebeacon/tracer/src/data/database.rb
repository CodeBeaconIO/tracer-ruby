# frozen_string_literal: true

require "sqlite3"
require "fileutils"
require_relative "tree_node_mapper"
require_relative "node_source_mapper"
require_relative "boundary_caller_mapper"

module Codebeacon
  module Tracer
    class DatabaseSchema
      def initialize(config)
        @config = config
        @db = initialize_db
      end

      def db
        @db
      end

      def initialize_db
        db_path = @config.db_path
        timestamp = Time.now.strftime("%Y%m%d%H%M%S")
        db_name = "#{@config.db_name}_#{timestamp}.db"
        db_symlink = File.join(db_path, "#{@config.db_name}.db")

        File.delete(db_symlink) if File.exist?(db_symlink)
        FileUtils.ln_sf(db_name, db_symlink)
        SQLite3::Database.new(File.join(db_path, db_name))
      end

      def create_tables
        MetadataMapper.create_table(db)
        TreeNodeMapper.create_table(db)
        NodeSourceMapper.create_table(db)
        BoundaryCallerMapper.create_table(db)
      end

      def create_indexes
        MetadataMapper.create_indexes(db)
        TreeNodeMapper.create_indexes(db)
        NodeSourceMapper.create_indexes(db)
        BoundaryCallerMapper.create_indexes(db)
      end

      def self.trim_db_files(config)
        db_path = config.db_path
        all_db_files = Dir.glob(File.join(db_path, "*.db"))
        all_db_files.reject! { |file| File.symlink?(file) }
        delete_count = all_db_files.length - config.max_db_files
        return if delete_count < 1
        
        pinned_file_names = load_pinned_recordings(config)
        db_files = all_db_files.select do |db_file|
          !pinned_file_names.include?(File.basename(db_file))
        end
        db_files.sort_by! { |db_file| File.birthtime(db_file) }

        delete_count.times do |i|
          File.delete(db_files[i])
        end
      end

      def self.load_pinned_recordings(config)
        pinned_path = config.pinned_recordings_path
        return [] unless File.exist?(pinned_path)

        begin
          data = YAML.load_file(pinned_path)
          data['pinned_recordings'] || []
        rescue => e
          []
        end
      end
    end
  end
end
