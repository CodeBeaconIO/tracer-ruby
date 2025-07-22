# frozen_string_literal: true

require "spec_helper"

RSpec.describe Codebeacon::Tracer::TypeDetector do
  describe ".basic_type?" do
    it "returns true for nil" do
      expect(described_class.basic_type?(nil)).to be true
    end

    it "returns true for basic types" do
      expect(described_class.basic_type?("hello")).to be true
      expect(described_class.basic_type?(42)).to be true
      expect(described_class.basic_type?(3.14)).to be true
      expect(described_class.basic_type?(:symbol)).to be true
      expect(described_class.basic_type?(true)).to be true
      expect(described_class.basic_type?(false)).to be true
    end

    it "returns false for non-basic types" do
      expect(described_class.basic_type?([1, 2, 3])).to be false
      expect(described_class.basic_type?({ key: "value" })).to be false
      custom_object = double("CustomObject")
      expect(described_class.basic_type?(custom_object)).to be false
    end
  end

  describe ".serializable_type?" do
    it "returns true for basic types" do
      expect(described_class.serializable_type?(nil)).to be true
      expect(described_class.serializable_type?("hello")).to be true
      expect(described_class.serializable_type?(42)).to be true
      expect(described_class.serializable_type?(3.14)).to be true
      expect(described_class.serializable_type?(:symbol)).to be true
      expect(described_class.serializable_type?(true)).to be true
      expect(described_class.serializable_type?(false)).to be true
    end

    it "returns false for non-basic types" do
      expect(described_class.serializable_type?([1, 2, 3])).to be false
      expect(described_class.serializable_type?({ key: "value" })).to be false
      custom_object = double("CustomObject")
      expect(described_class.serializable_type?(custom_object)).to be false
    end

    it "delegates to basic_type?" do
      expect(described_class).to receive(:basic_type?).with("test").and_return(true)
      described_class.serializable_type?("test")
    end
  end
end 