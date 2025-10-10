class TraceFile
  attr_reader :file_path, :klass

  def initialize(custom_contents, class_name: nil)
    @rand_str = next_random_integer_string
    @class_name = class_name || "SimpleClass#{@rand_str}"
    @file_path = "#{base_directory}/#{file_name}"
    contents_to_write = class_name ? custom_contents : custom_contents.gsub("CLASS_NAME", @class_name)
    create_file(contents_to_write)
  end

  def self.load!(custom_contents, class_name: nil)
    tf = new(custom_contents, class_name: class_name)
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

  protected

  def base_directory
    "./spec/tmp/fixtures"
  end

  def file_name
    "#{@class_name.downcase}.rb"
  end

  private

  def next_random_integer_string
    rand.to_s[2..]
  end

  def create_file(contents)
    FileUtils.mkdir_p(File.dirname(@file_path))
    File.write(@file_path, contents)
  end
end

class LibraryFile < TraceFile
  def self.dir
    "./spec/tmp/fixtures/library"
  end

  protected

  def base_directory
    self.class.dir
  end

  def file_name
    "library_#{@rand_str}.rb"
  end
end
