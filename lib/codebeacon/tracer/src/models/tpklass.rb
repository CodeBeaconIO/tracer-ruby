module Codebeacon
  module Tracer
    class TPKlass
      @@cache = {}
      
      def self.for_tp(tp)
        # Cache key based on class identity
        key = "#{tp.self.class.object_id}:#{tp.defined_class.object_id}"
        @@cache[key] ||= new(tp)
      end
      
      def self.clear_cache
        @@cache.clear
      end
      
      def initialize(tp)
        @tp = tp
      end

      def tp_class
        @tp_class ||= begin
          klass = @tp.self.class
          while klass && klass.to_s =~ /Class:0x/
            klass = klass.superclass
          end
          klass
        end
      end

      def defined_class
        @defined_class ||= begin
          klass = @tp.defined_class.to_s.sub("#<", "").sub(">", "")
          if klass.match(/^(Class|Module):/)
            klass = klass.split(":")[1..].join(":")
          elsif klass.match(/:0x[0-9a-f]+$/)
            klass = klass.split(":")[0..-2].join(":")
            klass += " Singleton"
          end
          klass
        end
      end

      def tp_class_name
        @tp_class_name ||= begin
          if @tp.self.is_a?(Module)
            @tp.self.name
          else
            klass = @tp.self.class
            while klass && klass.to_s =~ /Class:0x/
              klass = klass.superclass
            end
            klass.name
          end
        end
      end

      def type
        @type ||= case @tp.self
        when Class
          :Class
        when Module
          :Module
        when Object
          :Object
        else
          :Unknown
        end
      end
    end
  end
end