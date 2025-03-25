require 'spec_helper'

RSpec.describe Codebeacon::Tracer::NodeSource do
  before do
    Codebeacon::Tracer::NodeSource.clear
  end

  describe '.new' do
    it 'creates a new instance of Codebeacon::Tracer::NodeSource' do
      node_source = Codebeacon::Tracer::NodeSource.new('example', '/path/to/example')
      expect(node_source).to be_an_instance_of(Codebeacon::Tracer::NodeSource)
    end

    it 'sets the name and root_path attributes' do
      node_source = Codebeacon::Tracer::NodeSource.new('example', '/path/to/example')
      expect(node_source.name).to eq('example')
      expect(node_source.root_path).to eq('/path/to/example')
    end

    it 'adds the instance to the class instances array' do
      expect {
        Codebeacon::Tracer::NodeSource.new('example', '/path/to/example')
      }.to change { Codebeacon::Tracer::NodeSource.instances.size }.by(1)
    end
  end

  describe '.find' do
    let!(:app_source) { Codebeacon::Tracer::NodeSource.new('app', '/path/to/app') }
    let!(:gem_source) { Codebeacon::Tracer::NodeSource.new('gem', '/path/to/gem') }
    let!(:lib_source) { Codebeacon::Tracer::NodeSource.new('lib', '/path/to/lib') }

    it 'returns the node source for a path that matches exactly' do
      result = Codebeacon::Tracer::NodeSource.find('/path/to/app')
      expect(result).to eq(app_source)
    end

    it 'returns the node source for a path that is a subdirectory' do
      result = Codebeacon::Tracer::NodeSource.find('/path/to/app/controllers/users_controller.rb')
      expect(result).to eq(app_source)
    end

    it 'returns nil for a path that does not match any node source' do
      expect(Codebeacon::Tracer::NodeSource.find('/path/to/unknown')).to be_nil
    end

    it 'returns the most specific node source when multiple match' do
      specific_source = Codebeacon::Tracer::NodeSource.new('specific', '/path/to/app/controllers')
      expect(Codebeacon::Tracer::NodeSource.find('/path/to/app/controllers/users_controller.rb')).to eq(specific_source)
    end
  end

  describe '.clear' do
    before do
      Codebeacon::Tracer::NodeSource.new('app', '/path/to/app')
      Codebeacon::Tracer::NodeSource.new('gem', '/path/to/gem')
    end

    it 'clears all instances' do
      expect {
        Codebeacon::Tracer::NodeSource.clear
      }.to change { Codebeacon::Tracer::NodeSource.instances.size }.to(0)
    end
  end
end
