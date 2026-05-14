# frozen_string_literal: true

# Mimics the ActiveRecord/Sequel pattern: define a method via module_eval with
# string source on a normal class in a normal .rb file. The compiled method has
# a friendly tp.method_id (:attr_value) and tp.path == this file.
class GeneratedAccessors
  def initialize(value)
    @value = value
  end

  class_eval(<<~RUBY, __FILE__, __LINE__ + 1)
    def attr_value
      @value
    end
  RUBY
end
