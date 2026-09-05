# frozen_string_literal: true

require "time"

module Codebeacon
  module Tracer
    # Wraps a timestamped database filename following the convention
    # "<base>_<YYYYMMDDHHMMSS>.db" (e.g. "codebeacon_20260904123456.db").
    class DbFileName
      TIMESTAMP_FORMAT = "%Y%m%d%H%M%S"
      TIMESTAMP_PATTERN = /_(\d{14})\.db\z/

      def self.from_filename(filename)
        name = File.basename(filename)
        match = name.match(TIMESTAMP_PATTERN)
        return new(name.sub(/\.db\z/, ""), nil) unless match

        new(name.sub(TIMESTAMP_PATTERN, ""), Time.strptime(match[1], TIMESTAMP_FORMAT))
      end

      def initialize(base, time = Time.now)
        @base = base
        @time = time
      end

      def created_at
        @time
      end

      def to_s
        "#{@base}_#{@time.strftime(TIMESTAMP_FORMAT)}.db"
      end
    end
  end
end
