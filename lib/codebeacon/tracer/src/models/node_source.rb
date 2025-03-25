require 'pathname'

module Codebeacon
  module Tracer
    class NodeSource
      attr_accessor :id, :name, :root_path
      @instances = []

      class << self
        attr_accessor :instances
      end

      def initialize(name, root_path)
        @name = name
        @root_path = root_path
        self.class.instances << self
      end

      def self.find(path)
        return nil if path.nil?
        Pathname.new(path).ascend do |dir|
          source = self.instances.find { |ns| dir.to_s == ns.root_path }
          return source if source
        end
      end

      def self.clear
        self.instances = []
      end
    end
  end
end