# frozen_string_literal: true

module LangraphRuby
  module Execution
    class RetryPolicy
      attr_reader :max_retries, :initial_delay, :backoff_factor, :jitter, :retry_on

      # @param max_retries [Integer] Maximum number of retry attempts (default 3)
      # @param initial_delay [Float] Initial delay in seconds between retries (default 1.0)
      # @param backoff_factor [Float] Multiplier applied to delay after each retry (default 2.0)
      # @param jitter [Boolean] Add random jitter to delay to avoid thundering herd (default true)
      # @param retry_on [Proc, nil] Proc that receives an exception and returns true if it should be retried.
      #   Default: retry on all StandardError except GraphInterrupt
      def initialize(max_retries: 3, initial_delay: 1.0, backoff_factor: 2.0, jitter: true, retry_on: nil)
        @max_retries = max_retries
        @initial_delay = initial_delay
        @backoff_factor = backoff_factor
        @jitter = jitter
        @retry_on = retry_on || default_retry_on
      end

      # Execute a block with retry logic
      # @yield The block to execute
      # @return The block's return value
      def execute(&block)
        attempts = 0
        delay = @initial_delay

        begin
          attempts += 1
          block.call
        rescue GraphInterrupt
          raise # never retry interrupts
        rescue StandardError => e
          if attempts <= @max_retries && @retry_on.call(e)
            sleep(compute_delay(delay)) if delay > 0
            delay *= @backoff_factor
            retry
          end
          raise
        end
      end

      private

      def compute_delay(base_delay)
        if @jitter
          base_delay * (0.5 + rand * 0.5)
        else
          base_delay
        end
      end

      def default_retry_on
        ->(e) { e.is_a?(StandardError) && !e.is_a?(GraphInterrupt) }
      end
    end
  end
end
