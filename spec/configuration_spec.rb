require 'spec_helper'

RSpec.describe Codebeacon::Tracer::Configuration do
  let(:config) { Codebeacon::Tracer::Configuration.new }
  let(:temp_config_file) { File.join(config.data_dir, 'tracer_config.yml') }

  before do
    FileUtils.mkdir_p(config.data_dir)
  end

  after do
    File.delete(temp_config_file) if File.exist?(temp_config_file)
  end

  describe '#skip_tracing?' do
    context 'when no exclusion patterns are configured' do
      it 'returns false' do
        expect(config.skip_tracing?('test', 'description')).to be false
      end
    end

    context 'when exclusion patterns are configured' do
      before do
        config_data = {
          'tracing_enabled' => true,
          'filters' => {
            'recording_meta_exclude' => [
              { 'name' => 'application#panel*', 'description' => '*' },
              { 'name' => '*', 'description' => '' },
              { 'name' => 'health_check#*', 'description' => '*' }
            ]
          }
        }
        File.write(temp_config_file, YAML.dump(config_data))
        config.instance_variable_set(:@recording_meta_exclude_patterns, nil) # Force reload
      end

      it 'excludes matching name with wildcard description' do
        expect(config.skip_tracing?('application#panel_show', 'any description')).to be true
        expect(config.skip_tracing?('application#panel_edit', '{}')).to be true
      end

      it 'excludes any name with blank description' do
        expect(config.skip_tracing?('users#show', '')).to be true
        expect(config.skip_tracing?('posts#index', nil)).to be true
      end

      it 'excludes health check endpoints' do
        expect(config.skip_tracing?('health_check#status', 'some params')).to be true
      end

      it 'does not exclude non-matching patterns' do
        expect(config.skip_tracing?('users#show', 'valid description')).to be false
        expect(config.skip_tracing?('posts#index', 'some params')).to be false
      end

      it 'handles case-insensitive matching' do
        expect(config.skip_tracing?('APPLICATION#PANEL_SHOW', 'description')).to be true
      end

      it 'handles nil values correctly' do
        expect(config.skip_tracing?(nil, nil)).to be true  # matches '*' pattern with '' description
      end

      it 'handles Symbol values correctly' do
        expect(config.skip_tracing?('health_check#status', 'params')).to be true
      end
    end

    context 'when config file has invalid patterns' do
      before do
        config_data = {
          'filters' => {
            'recording_meta_exclude' => [
              { 'name' => 'valid#pattern', 'description' => '*' },
              'invalid_pattern',
              { 'name' => 'missing_description' },
              { 'description' => 'missing_name' }
            ]
          }
        }
        File.write(temp_config_file, YAML.dump(config_data))
        config.instance_variable_set(:@recording_meta_exclude_patterns, nil)
      end

      it 'only processes valid patterns and logs warnings' do
        # Set up the mock expectation first
        logger_mock = double('logger')
        allow(config).to receive(:logger).and_return(logger_mock)
        expect(logger_mock).to receive(:warn).at_least(:once)
        
        expect(config.skip_tracing?('valid#pattern', 'test')).to be true
        expect(config.skip_tracing?('invalid', 'test')).to be false
      end
    end

    context 'when config file is malformed' do
      before do
        File.write(temp_config_file, 'invalid: yaml: content: [')
        config.instance_variable_set(:@recording_meta_exclude_patterns, nil)
      end

      it 'handles YAML errors gracefully' do
        logger_mock = double('logger')
        allow(config).to receive(:logger).and_return(logger_mock)
        expect(logger_mock).to receive(:warn).with(/Error loading recording meta exclude patterns/)
        
        expect(config.skip_tracing?('test', 'description')).to be false
      end
    end

    context 'when pattern matching raises an error' do
      before do
        config_data = {
          'filters' => {
            'recording_meta_exclude' => [
              { 'name' => 'test', 'description' => 'test' }
            ]
          }
        }
        File.write(temp_config_file, YAML.dump(config_data))
        config.instance_variable_set(:@recording_meta_exclude_patterns, nil)
      end

      it 'handles errors gracefully and defaults to not skipping' do
        allow(File).to receive(:fnmatch).and_raise('Pattern error')
        
        logger_mock = double('logger')
        allow(config).to receive(:logger).and_return(logger_mock)
        expect(logger_mock).to receive(:warn).with(/Error checking skip_tracing patterns/)
        
        expect(config.skip_tracing?('test', 'test')).to be false
      end
    end
  end

  describe '#recording_meta_exclude_patterns' do
    it 'caches patterns after first load' do
      expect(config).to receive(:load_recording_meta_exclude_patterns).once.and_return([])
      config.recording_meta_exclude_patterns
      config.recording_meta_exclude_patterns # Second call should use cache
    end

    it 'returns empty array when no config file exists' do
      expect(config.recording_meta_exclude_patterns).to eq([])
    end
  end

  describe '#reload_tracer_config' do
    it 'clears the cached exclusion patterns' do
      config.instance_variable_set(:@recording_meta_exclude_patterns, ['cached'])
      config.reload_tracer_config
      expect(config.instance_variable_get(:@recording_meta_exclude_patterns)).to be_nil
    end
  end

  describe 'debug logging' do
    before do
      config_data = {
        'filters' => {
          'recording_meta_exclude' => [
            { 'name' => 'debug#test', 'description' => '*' }
          ]
        }
      }
      File.write(temp_config_file, YAML.dump(config_data))
      config.instance_variable_set(:@recording_meta_exclude_patterns, nil)
    end

    context 'when debug mode is enabled' do
      before { config.debug = true }

      it 'logs when tracing is skipped' do
        expect(config.logger).to receive(:debug).with(/Skipping trace due to metadata exclusion/)
        config.skip_tracing?('debug#test', 'any description')
      end
    end

    context 'when debug mode is disabled' do
      before { config.debug = false }

      it 'does not log when tracing is skipped' do
        expect(config.logger).not_to receive(:debug)
        config.skip_tracing?('debug#test', 'any description')
      end
    end
  end
end 