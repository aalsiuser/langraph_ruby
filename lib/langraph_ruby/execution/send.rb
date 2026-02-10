# frozen_string_literal: true

module LangraphRuby
  module Execution
    # Send enables dynamic parallel execution by specifying a target node
    # and the state to pass to it. Return one or more Send objects from
    # a node to create dynamic fan-out patterns (map-reduce).
    #
    # @example Fan-out to process multiple items
    #   items.map { |item| Send.new(node: :process, state: { item: item }) }
    #
    # @example Single dynamic edge
    #   Send.new(node: :specialist, state: { query: "specific question" })
    class Send
      attr_reader :node, :state

      # @param node [Symbol] Target node to execute
      # @param state [Hash] State to pass to the target node (merged into current state)
      def initialize(node:, state: {})
        @node = node.to_sym
        @state = state
      end

      def send?
        true
      end
    end
  end
end
