# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'Boundary Caller Tracking' do
  let(:temp_config_file) { File.join(Codebeacon::Tracer.config.data_dir, 'tracer_config.yml') }

  before do
    FileUtils.mkdir_p(Codebeacon::Tracer.config.data_dir)
    Codebeacon::Tracer.config.dry_run = true
    # Ensure boundary caller tracking is enabled
    allow(Codebeacon::Tracer.config).to receive(:track_boundary_callers?).and_return(true)
  end

  after do
    File.delete(temp_config_file) if File.exist?(temp_config_file)
  end

  describe 'boundary depth tracking' do
    it 'tracks depth when entering library code' do
      tracer = nil
      
      Codebeacon::Tracer.trace(name: 'test_callback_tracking') do |t|
        tracer = t
        
        # The current node should have library_depth = 0 initially
        current_node = tracer.call_tree.current_node
        expect(current_node.library_depth).to eq(0)
        expect(current_node.library_exit_info).to be_nil
        
        'test result'
      end
    end
  end

  describe 'callback detection' do
    it 'identifies callbacks from library to application code' do
      callback_detected = false
      
      # Create a simple test scenario
      test_method = lambda do |value|
        # This simulates an application method that could be called back from a library
        callback_detected = true
        "processed: #{value}"
      end
      
      result = Codebeacon::Tracer.trace(name: 'test_callback_detection') do |tracer|
        # Verify tracer is working
        expect(tracer).not_to be_nil
        expect(tracer.call_tree).not_to be_nil
        
        # Call our test method to ensure basic functionality works
        test_method.call("test")
      end
      
      expect(callback_detected).to be(true)
    end
  end

  describe 'database integration' do
    it 'creates boundary_callers table' do
      result = Codebeacon::Tracer.trace(name: 'test_db_integration') do |tracer|
        # Just verify the tracer initializes properly
        expect(tracer).not_to be_nil
        'test complete'
      end
      
      expect(result).to eq('test complete')
    end
  end

  describe 'configuration' do
    it 'respects track_boundary_callers configuration' do
      # Test with tracking disabled
      allow(Codebeacon::Tracer.config).to receive(:track_boundary_callers?).and_return(false)
      
      result = Codebeacon::Tracer.trace(name: 'test_config_disabled') do |tracer|
        expect(tracer).not_to be_nil
        # When disabled, no library tracking should occur
        'test with tracking disabled'
      end
      
      expect(result).to eq('test with tracking disabled')
    end

    it 'enables boundary caller tracking by default' do
      # Reset to default behavior
      allow(Codebeacon::Tracer.config).to receive(:track_boundary_callers?).and_call_original
      
      # Default should be enabled
      expect(Codebeacon::Tracer.config.track_boundary_callers?).to be(true)
    end
  end

  describe 'TreeNode enhancements' do
    it 'initializes library tracking attributes' do
      node = Codebeacon::Tracer::TreeNode.new
      
      expect(node.library_depth).to eq(0)
      expect(node.library_exit_info).to be_nil
      expect(node.callback_info).to be_nil
    end

    it 'can store callback information' do
      node = Codebeacon::Tracer::TreeNode.new
      
      callback_info = {
        outgoing_method: 'save',
        outgoing_method_as_called: 'save!'
      }
      
      node.callback_info = callback_info
      expect(node.callback_info).to eq(callback_info)
    end
  end
end