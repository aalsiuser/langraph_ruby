# frozen_string_literal: true

module LangraphRuby
  module State
    class StateSnapshot
      attr_reader :values, :next_nodes, :step

      def initialize(values:, next_nodes: [], step: 0)
        @values = values.freeze
        @next_nodes = next_nodes.freeze
        @step = step
      end

      def [](key)
        @values[key.to_sym]
      end

      def to_h
        { values: @values, next_nodes: @next_nodes, step: @step }
      end
    end
  end
end
