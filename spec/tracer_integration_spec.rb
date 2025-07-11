require 'spec_helper'

RSpec.describe 'Tracer Integration with Metadata Exclusion' do
  let(:temp_config_file) { File.join(Codebeacon::Tracer.config.data_dir, 'tracer_config.yml') }

  before do
    FileUtils.mkdir_p(Codebeacon::Tracer.config.data_dir)
    Codebeacon::Tracer.config.dry_run = true
  end

  after do
    File.delete(temp_config_file) if File.exist?(temp_config_file)
  end

  context 'when tracing is excluded by metadata' do
    before do
      config_data = {
        'tracing_enabled' => true,
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => 'excluded#*', 'description' => '*' },
            { 'name' => '*', 'description' => 'skip_this' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data))
      Codebeacon::Tracer.config.reload_tracer_config
    end

    it 'does not perform tracing setup for excluded recordings' do
      # Mock the setup method to verify it's not called
      expect(Codebeacon::Tracer).not_to receive(:setup)
      
      result = Codebeacon::Tracer.trace(name: 'excluded#action', description: 'some description') do |tracer|
        expect(tracer).to be_nil
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end

    it 'excludes based on description pattern' do
      expect(Codebeacon::Tracer).not_to receive(:setup)
      
      result = Codebeacon::Tracer.trace(name: 'any_action', description: 'skip_this') do |tracer|
        expect(tracer).to be_nil
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end

    it 'performs tracing for non-excluded recordings' do
      # Allow the setup method to be called for non-excluded traces
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      allow(Codebeacon::Tracer).to receive(:persist).and_call_original
      
      Codebeacon::Tracer.trace(name: 'allowed#action', description: 'some description') do |tracer|
        expect(tracer).not_to be_nil
        expect(tracer).to be_a(Codebeacon::Tracer::Tracer)
        'test_result'
      end
    end

    it 'handles nil name and description correctly' do
      # This should not be excluded since our patterns don't match nil -> '' conversion
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      allow(Codebeacon::Tracer).to receive(:persist).and_call_original
      
      Codebeacon::Tracer.trace() do |tracer|
        expect(tracer).not_to be_nil
        'test_result'
      end
    end
  end

  context 'when no exclusion patterns are configured' do
    before do
      config_data = {
        'tracing_enabled' => true
      }
      File.write(temp_config_file, YAML.dump(config_data))
      Codebeacon::Tracer.config.reload_tracer_config
    end

    it 'performs normal tracing' do
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      allow(Codebeacon::Tracer).to receive(:persist).and_call_original
      
      Codebeacon::Tracer.trace(name: 'test_action', description: 'test description') do |tracer|
        expect(tracer).not_to be_nil
        expect(tracer).to be_a(Codebeacon::Tracer::Tracer)
        'test_result'
      end
    end
  end

  context 'when tracing is disabled globally' do
    before do
      config_data = {
        'tracing_enabled' => false,
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => '*', 'description' => '*' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data))
      Codebeacon::Tracer.config.reload_tracer_config
    end

    it 'skips tracing before checking exclusion patterns' do
      expect(Codebeacon::Tracer.config).not_to receive(:skip_tracing?)
      
      result = Codebeacon::Tracer.trace(name: 'any_action', description: 'any description') do |tracer|
        expect(tracer).to be_nil
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end
  end

  context 'when exclusion pattern check raises an error' do
    before do
      config_data = {
        'tracing_enabled' => true,
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => 'test', 'description' => 'test' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data))
      Codebeacon::Tracer.config.reload_tracer_config
    end

    it 'continues with tracing when exclusion check fails' do
      # Mock File.fnmatch to raise an error
      allow(File).to receive(:fnmatch).and_raise('Pattern error')
      
      # Should continue with tracing despite the error
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      allow(Codebeacon::Tracer).to receive(:persist).and_call_original
      
      result = Codebeacon::Tracer.trace(name: 'test', description: 'test') do |tracer|
        expect(tracer).not_to be_nil
        'test_result'
      end
      
      expect(result).to eq('test_result')
    end
  end

  context 'complex pattern matching scenarios' do
    before do
      config_data = {
        'tracing_enabled' => true,
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => 'admin#*', 'description' => '*sensitive*' },
            { 'name' => 'api#v[12]#*', 'description' => '*' },
            { 'name' => '*health*', 'description' => '' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data))
      Codebeacon::Tracer.config.reload_tracer_config
    end

    it 'matches complex glob patterns correctly' do
      # Should be excluded - admin action with sensitive data
      expect(Codebeacon::Tracer).not_to receive(:setup)
      Codebeacon::Tracer.trace(name: 'admin#users', description: 'contains_sensitive_data') do |tracer|
        expect(tracer).to be_nil
      end

      # Should be excluded - API v1 endpoint  
      expect(Codebeacon::Tracer).not_to receive(:setup)
      Codebeacon::Tracer.trace(name: 'api#v1#users', description: 'any description') do |tracer|
        expect(tracer).to be_nil
      end

      # Should be excluded - health check with empty description
      expect(Codebeacon::Tracer).not_to receive(:setup)
      Codebeacon::Tracer.trace(name: 'app_health_check') do |tracer|
        expect(tracer).to be_nil
      end
    end

    it 'does not exclude non-matching patterns' do
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      allow(Codebeacon::Tracer).to receive(:persist).and_call_original

      # Should NOT be excluded - admin without sensitive data
      Codebeacon::Tracer.trace(name: 'admin#users', description: 'normal operation') do |tracer|
        expect(tracer).not_to be_nil
      end

      # Should NOT be excluded - API v3 (not matching v[12] pattern)
      Codebeacon::Tracer.trace(name: 'api#v3#users', description: 'any description') do |tracer|
        expect(tracer).not_to be_nil
      end

      # Should NOT be excluded - health check with description
      Codebeacon::Tracer.trace(name: 'app_health_check', description: 'detailed check') do |tracer|
        expect(tracer).not_to be_nil
      end
    end
  end

  context 'post-trace filtering (useful for Rails middleware)' do
    before do
      config_data = {
        'tracing_enabled' => true,
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => 'rails#excluded_*', 'description' => '*' },
            { 'name' => 'users#*', 'description' => 'admin_operation' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data))
      Codebeacon::Tracer.config.reload_tracer_config
    end

    it 'performs tracing but skips persistence when metadata is excluded' do
      # Setup should be called since we're allowing tracing to proceed initially
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      
      # Mock the database operations to verify they're not called due to post-trace filtering
      expect(Codebeacon::Tracer::DatabaseSchema).not_to receive(:new)
      
      Codebeacon::Tracer.trace do |tracer|
        expect(tracer).not_to be_nil
        expect(tracer).to be_a(Codebeacon::Tracer::Tracer)
        
        # Set metadata that will be excluded during persistence
        tracer.name = 'rails#excluded_action'
        tracer.description = 'request parameters'
        
        'test_result'
      end
    end

    it 'performs both tracing and persistence when metadata is not excluded' do
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      
      # Temporarily disable dry_run to test actual persistence logic
      original_dry_run = Codebeacon::Tracer.config.dry_run?
      Codebeacon::Tracer.config.dry_run = false
      
      # Expect database operations to be called for non-excluded traces
      expect(Codebeacon::Tracer::DatabaseSchema).to receive(:new).and_call_original
      
      begin
        Codebeacon::Tracer.trace do |tracer|
          expect(tracer).not_to be_nil
          
          # Set metadata that will NOT be excluded
          tracer.name = 'users#show'
          tracer.description = 'normal_operation'
          
          'test_result'
        end
      ensure
        Codebeacon::Tracer.config.dry_run = original_dry_run
      end
    end

    it 'works with start/stop workflow when tracer has metadata' do
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      
      # Should not persist when metadata is excluded
      expect(Codebeacon::Tracer::DatabaseSchema).not_to receive(:new)
      
      Codebeacon::Tracer.start
      
      # Set metadata on the tracer
      Codebeacon::Tracer.instance_variable_get(:@tracer).name = 'rails#excluded_manual'
      Codebeacon::Tracer.instance_variable_get(:@tracer).description = 'manual trace'
      
      Codebeacon::Tracer.stop
    end

    it 'logs debug message when persistence is skipped' do
      config_data_with_debug = {
        'tracing_enabled' => true,
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => 'debug#test', 'description' => '*' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data_with_debug))
      Codebeacon::Tracer.config.reload_tracer_config
      Codebeacon::Tracer.config.debug = true
      
      # Temporarily disable dry_run to test actual exclusion logic
      original_dry_run = Codebeacon::Tracer.config.dry_run?
      Codebeacon::Tracer.config.dry_run = false
      
      allow(Codebeacon::Tracer).to receive(:setup).and_call_original
      allow(Codebeacon::Tracer).to receive(:cleanup).and_call_original
      
      # Use a more flexible expectation that allows other debug messages
      expect(Codebeacon::Tracer.config.logger).to receive(:debug).with(/Skipping persistence due to metadata exclusion/).at_least(:once)
      allow(Codebeacon::Tracer.config.logger).to receive(:debug)  # Allow other debug messages
      
      begin
        Codebeacon::Tracer.trace do |tracer|
          tracer.name = 'debug#test'
          tracer.description = 'test description'
          'test_result'
        end
      ensure
        Codebeacon::Tracer.config.dry_run = original_dry_run
      end
    end
  end
end 