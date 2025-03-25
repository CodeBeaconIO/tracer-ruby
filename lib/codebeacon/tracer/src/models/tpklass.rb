module Codebeacon
  module Tracer
    class TPKlass
      def initialize(tp)
        @tp = tp
      end

      def tp_class
        klass = @tp.self.class
        while klass && klass.to_s =~ /Class:0x/
          klass = klass.superclass
        end
        klass
      end

      def defined_class
        klass = @tp.defined_class.to_s.sub("#<", "").sub(">", "")
        if klass.match(/^(Class|Module):/)
          klass = klass.split(":")[1..].join(":")
        elsif klass.match(/:0x[0-9a-f]+$/)
          klass = klass.split(":")[0..-2].join(":")
          klass += " Singleton"
        end
        klass
      end

      def tp_class_name
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

      def type
        case @tp.self
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