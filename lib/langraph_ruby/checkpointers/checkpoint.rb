# frozen_string_literal: true

require "securerandom"

module LangraphRuby
  module Checkpointers
    class Checkpoint
      attr_reader :id, :thread_id, :parent_id, :state, :next_nodes,
                  :step, :metadata, :created_at, :interrupted_node,
                  :interrupt_value, :pending_writes

      def initialize(
        thread_id:, state:, next_nodes: [], step: 0,
        id: nil, parent_id: nil, metadata: {},
        interrupted_node: nil, interrupt_value: nil,
        pending_writes: nil, created_at: nil
      )
        @id = id || SecureRandom.uuid
        @thread_id = thread_id
        @parent_id = parent_id
        @state = state
        @next_nodes = next_nodes
        @step = step
        @metadata = metadata
        @interrupted_node = interrupted_node
        @interrupt_value = interrupt_value
        @pending_writes = pending_writes
        @created_at = created_at || Time.now
      end

      def interrupted?
        !@interrupted_node.nil?
      end

      def to_h
        {
          id: @id,
          thread_id: @thread_id,
          parent_id: @parent_id,
          state: @state,
          next_nodes: @next_nodes,
          step: @step,
          metadata: @metadata,
          interrupted_node: @interrupted_node,
          interrupt_value: @interrupt_value,
          pending_writes: @pending_writes,
          created_at: @created_at.iso8601
        }
      end
    end
  end
end
