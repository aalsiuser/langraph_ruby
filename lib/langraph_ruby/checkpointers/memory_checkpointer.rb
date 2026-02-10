# frozen_string_literal: true

module LangraphRuby
  module Checkpointers
    class MemoryCheckpointer < BaseCheckpointer
      def initialize
        @storage = {} # thread_id => [checkpoints]
      end

      def save(checkpoint)
        @storage[checkpoint.thread_id] ||= []
        @storage[checkpoint.thread_id] << checkpoint
        checkpoint
      end

      def load(thread_id)
        checkpoints = @storage[thread_id]
        return nil unless checkpoints&.any?

        checkpoints.last
      end

      def load_by_id(thread_id, checkpoint_id)
        checkpoints = @storage[thread_id]
        return nil unless checkpoints

        checkpoints.find { |c| c.id == checkpoint_id }
      end

      def list(thread_id)
        (@storage[thread_id] || []).reverse
      end

      def delete(thread_id)
        @storage.delete(thread_id)
      end

      def thread_ids
        @storage.keys
      end
    end
  end
end
