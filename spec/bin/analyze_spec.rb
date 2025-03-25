require 'spec_helper'
require 'open3'

RSpec.describe 'bin/analyze' do
  let(:analyze_script) { File.join(__dir__, '../../bin/analyze') }
  let(:test_script) { File.join(__dir__, '../../spec/data/test_script.rb') }
  
  before do
    # Create a simple test script
    File.write(test_script, <<~RUBY)
      def test_method
        puts "Hello from test script"
      end
      test_method
    RUBY
  end

  after do
    File.delete(test_script) if File.exist?(test_script)
  end

  it 'can execute a Ruby script' do
    stdout, stderr, status = Open3.capture3(analyze_script, test_script)
    expect(status.success?).to be true
    expect(stdout).to include("Hello from test script")
  end

  it 'fails when no script is provided' do
    stdout, stderr, status = Open3.capture3(analyze_script)
    expect(status.success?).to be false
    expect(stderr).to include("load")
  end
end 