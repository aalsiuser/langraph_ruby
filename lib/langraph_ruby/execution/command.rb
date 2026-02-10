# frozen_string_literal: true

module LangraphRuby
  module Execution
    # Command combines state updates with explicit routing control.
    # Return a Command from a node to simultaneously update state
    # AND specify which node(s) to execute next.
    #
    # @example Route to a specific node
    #   Command.new(goto: :reviewer, update: { draft: "Hello" })
    #
    # @example Route to END
    #   Command.new(goto: LangraphRuby::END_, update: { done: true })
    #
    # @example Route to multiple nodes (parallel fan-out)
    #   Command.new(goto: [:research, :write], update: { started: true })
    class Command
      attr_reader :goto, :update

      # @param goto [Symbol, Array<Symbol>] Target node(s) to execute next
      # @param update [Hash] State update to apply before routing
      def initialize(goto:, update: {})
        @goto = goto.is_a?(Array) ? goto.map(&:to_sym) : [goto.to_sym]
        @update = update
      end

      def command?
        true
      end
    end
  end
end
