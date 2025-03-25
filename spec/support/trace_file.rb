class TraceFile
  attr_reader :file_path, :klass

  def initialize(custom_contents)
    @rand_str = next_random_integer_string
    @class_name = "SimpleClass#{@rand_str}"
    @file_path = "./spec/tmp/fixtures/#{@class_name.downcase}.rb"
    create_file(custom_contents)
  end

  def self.load!(custom_contents)
    tf = new(custom_contents)
    tf.require_file
    return tf
  end

  def cleanup
    Object.send(:remove_const, @class_name.to_sym) if Object.const_defined?(@class_name.to_sym)
    File.delete(@file_path) if File.exist?(@file_path)
  end

  def require_file
    require @file_path
    @klass = Object.const_get(@class_name)
  end

  private def next_random_integer_string
    rand.to_s[2..]
  end

  private def create_file(custom_contents)
    FileUtils.mkdir_p(File.dirname(@file_path))
    File.write(@file_path, custom_contents.gsub("CLASS_NAME", @class_name))
  end
end
