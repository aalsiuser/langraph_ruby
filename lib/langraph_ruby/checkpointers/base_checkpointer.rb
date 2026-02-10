# frozen_string_literal: true

module LangraphRuby
  module Checkpointers
    class BaseCheckpointer
      # Save a checkpoint
      # @param checkpoint [Checkpoint]
      def save(checkpoint)
        raise NotImplementedError
      end

      # Load the latest checkpoint for a thread
      # @param thread_id [String]
      # @return [Checkpoint, nil]
      def load(thread_id)
        raise NotImplementedError
      end

      # Load a specific checkpoint by ID
      # @param thread_id [String]
      # @param checkpoint_id [String]
      # @return [Checkpoint, nil]
      def load_by_id(thread_id, checkpoint_id)
        raise NotImplementedError
      end

      # List all checkpoints for a thread (newest first)
      # @param thread_id [String]
      # @return [Array<Checkpoint>]
      def list(thread_id)
        raise NotImplementedError
      end

      # Delete all checkpoints for a thread
      # @param thread_id [String]
      def delete(thread_id)
        raise NotImplementedError
      end
    end
  end
end
