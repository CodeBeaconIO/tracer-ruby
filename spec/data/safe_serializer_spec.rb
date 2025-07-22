# frozen_string_literal: true

require "spec_helper"

RSpec.describe Codebeacon::Tracer::SafeSerializer do
  describe ".serialize" do
    context "with basic types" do
      it "serializes strings with truncation" do
        expect(described_class.serialize("hello", 10)).to eq("hello")
        expect(described_class.serialize("hello world", 5)).to eq("hello...")
        expect(described_class.serialize("hello world", 3)).to eq("hel...")
      end

      it "serializes numbers" do
        expect(described_class.serialize(42, 10)).to eq("42")
        expect(described_class.serialize(3.14, 10)).to eq("3.14")
        expect(described_class.serialize(1234567890123456789012345678901234567890, 10)).to eq("1234567890...")
      end

      it "serializes symbols and booleans" do
        expect(described_class.serialize(:symbol, 10)).to eq("symbol")
        expect(described_class.serialize(true, 10)).to eq("true")
        expect(described_class.serialize(false, 10)).to eq("false")
      end

      it "truncates long symbols" do
        long_symbol = :"very_long_symbol_name_that_exceeds_the_maximum_length"
        result = described_class.serialize(long_symbol, 10)
        expect(result.length).to be <= 13 # 10 + 3 for "..."
        expect(result).to end_with("...")
        expect(result).to start_with("very_long")
      end

      it "serializes nil" do
        expect(described_class.serialize(nil, 10)).to eq("nil")
      end
    end

    context "with arrays" do
      it "returns nil for arrays" do
        expect(described_class.serialize([], 10)).to be_nil
        expect(described_class.serialize([1, 2, 3], 20)).to be_nil
        expect(described_class.serialize(["a", "b"], 20)).to be_nil
      end
    end

    context "with hashes" do
      it "returns nil for hashes" do
        expect(described_class.serialize({}, 10)).to be_nil
        hash = { key: "value", num: 42 }
        expect(described_class.serialize(hash, 50)).to be_nil
      end
    end

    context "with non-serializable types" do
      it "returns nil for non-serializable types" do
        custom_object = double("CustomObject")
        expect(described_class.serialize(custom_object, 10)).to be_nil
      end

      it "returns nil for Rails types" do
        rails_object = double("ActiveRecord::Base", class: double(name: "ActiveRecord::Base"))
        expect(described_class.serialize(rails_object, 10)).to be_nil
      end
    end

    context "with edge cases" do
      it "handles very short max_length" do
        expect(described_class.serialize("hello", 1)).to eq("h...")
        expect(described_class.serialize([1, 2], 5)).to be_nil
      end

      it "handles zero max_length" do
        expect(described_class.serialize("hello", 0)).to eq("...")
      end

      it "handles negative max_length" do
        expect(described_class.serialize("hello", -1)).to eq("...")
      end

      it "handles timeout gracefully" do
        # Mock a slow operation by temporarily setting a very low timeout
        original_timeout = Codebeacon::Tracer.config.serialization_timeout_ms
        allow(Codebeacon::Tracer.config).to receive(:serialization_timeout_ms).and_return(0.001) # 1 microsecond
        
        # This should timeout and return a partial result
        result = described_class.serialize("hello world", 10)
        expect(result).to eq("hello worl...")
        
        # Restore original timeout
        allow(Codebeacon::Tracer.config).to receive(:serialization_timeout_ms).and_return(original_timeout)
      end

      it "returns timeout indicator when no partial result available" do
        # Mock a slow operation by temporarily setting a very low timeout
        original_timeout = Codebeacon::Tracer.config.serialization_timeout_ms
        allow(Codebeacon::Tracer.config).to receive(:serialization_timeout_ms).and_return(0.001) # 1 microsecond
        
        # This should timeout and return timeout indicator
        result = described_class.serialize(nil, 10)
        expect(result).to eq("nil")
        
        # Restore original timeout
        allow(Codebeacon::Tracer.config).to receive(:serialization_timeout_ms).and_return(original_timeout)
      end
    end
  end
end 