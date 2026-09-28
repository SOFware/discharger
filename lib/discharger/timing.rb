# frozen_string_literal: true

module Discharger
  module Timing
    # Seconds the block took, from the monotonic clock.
    def self.measure
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      yield
      Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
    end
  end
end
