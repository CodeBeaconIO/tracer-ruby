require 'fileutils'
require 'yaml'

module Codebeacon
  module Tracer
    class Configuration
      MAX_DB_FILES = 100
      RETURN_VAL_MAX_LENGTH = 1000
      MAX_CALL_COUNT = 100000000
      MAX_DEPTH = 99999

      def initialize()
        @query = ""
        @exclude_paths = []
        ensure_db_path
      end

      def setup
        exclude_paths << lib_root
        reload_paths_to_record
        load_main_config
      end

      def load_main_config
        if File.exist?(config_path)
          config_data = YAML.load_file(config_path)
          load_exclude_paths(config_data['exclude'])
        end
      end

      def load_exclude_paths(excludes)
        return if excludes.nil?
        (excludes['paths'] || []).each { |path| exclude_paths << path }
        (excludes['gems'] || []).each do |gem_name|
          Gem::Specification.find_all_by_name(gem_name).each do |gem_spec|
            exclude_paths << gem_spec.gem_dir
          end
        end
      end

      def set_query_config(query)
        @query = query || ""
        # self.trace_enabled = @query.include?('rf__trace_enabled=true')
        self.debug = @query.include?('rf__debug=true')
        self.dry_run = @query.include?('rf__dry_run=true')
        # self.local_methods_only = @query.include?('rf__local_methods_only=true')
        # self.local_lines_only = @query.include?('rf__local_lines_only=true')
      end

      def ensure_db_path
        FileUtils.mkpath(db_path)
      end

      # def load_ruby_flow_config
      #   if File.exist?('.code-beacon.yml')
      #     @config = YAML.load_file('.code-beacon.yml')
      #   end
      # end

      def lib_root
        File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..'))
      end

      def data_dir
        ".code-beacon"
      end

      def db_path
       File.join(data_dir, "db")
      end

      def tmp_dir
        File.join(data_dir, "tmp")
      end

      def refresh_path
        File.join(data_dir, "tmp", "refresh")
      end

      def paths_path
        File.join(data_dir, "paths.yml")
      end

      def config_path
        File.expand_path(File.join(lib_root, 'config.yml')) 
      end

      def read_paths
        if File.exist?(paths_path)
          YAML.load_file(paths_path)
        end
      end

      def db_name
        "codebeacon_tracer"
      end

      def max_db_files
        MAX_DB_FILES
      end

      def gem_path
        @gem_path ||= ENV['GEM_HOME'] || Gem.paths.home
      end

      def root_path
        @root_path ||= defined?(Rails) ? Rails.root.to_s : Dir.pwd
      end

      def rubylib_path
        @rubylib_path ||= RbConfig::CONFIG['rubylibdir']
      end

      def paths_to_record
        @paths_to_record ||= [Codebeacon::Tracer.config.root_path, *Codebeacon::Tracer.config.read_paths]
      end

      def reload_paths_to_record
        @paths_to_record = nil
        paths_to_record
      end

      def exclude_paths(*paths)
        @exclude_paths += paths
      end

      def trace_enabled?
        # @trace_enabled
        true
      end

      def trace_enabled=(value)
        @trace_enabled = value
      end

      def debug?
        @debug
      end

      def debug=(value)
        Codebeacon::Tracer.logger.level = value ? ::Logger::DEBUG : ::Logger::INFO
        @debug = value
      end

      def dry_run?
        @dry_run
      end

      def dry_run=(value)
        @dry_run = value
      end

      def local_methods_only?
        # @local_methods_only
        true
      end

      def local_methods_only=(value)
        @local_methods_only = value
      end

      def local_lines_only?
        # @local_lines_only
        true
      end

      def local_lines_only=(value)
        @local_lines_only = value
      end
      
      def skip_internal?
        true
      end

      def max_value_length
        RETURN_VAL_MAX_LENGTH
      end

      def max_call_count
        MAX_CALL_COUNT
      end

      def max_depth
        MAX_DEPTH
      end

      def logger
        @logger ||= Codebeacon::Tracer::Logger.new()
      end

      def debug_something
        #### debug return
        # @return_count += 1
        # Codebeacon::Tracer.logger.info("Call count: #{@return_count}")
        # Codebeacon::Tracer.logger.info("Return @depth: #{@depth}, method: #{tp.method_id}, line: #{tp.lineno}, path: #{tp.path}")
      end
    end
  end
end