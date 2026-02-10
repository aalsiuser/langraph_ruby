# frozen_string_literal: true

module LangraphRuby
  module Graph
    # Wraps a CompiledGraph so it can be used as a node inside a parent graph.
    # The subgraph receives the parent state, executes its full graph,
    # and returns the resulting state as the node's update.
    #
    # @example
    #   research_graph = StateGraph.new { ... }.compile
    #   parent = StateGraph.new
    #   parent.add_node(:research, Subgraph.new(research_graph))
    #
    # @example With input/output key mapping
    #   Subgraph.new(child_graph,
    #     input_map: { parent_query: :query },    # parent :parent_query → child :query
    #     output_map: { result: :research_result } # child :result → parent :research_result
    #   )
    class Subgraph
      # @param compiled_graph [Execution::CompiledGraph] The compiled child graph
      # @param input_map [Hash] Map parent state keys to child input keys
      # @param output_map [Hash] Map child output keys to parent state keys
      def initialize(compiled_graph, input_map: nil, output_map: nil)
        @compiled_graph = compiled_graph
        @input_map = input_map
        @output_map = output_map
      end

      # Callable interface — acts as a node function
      def call(state)
        child_input = build_child_input(state)
        child_output = @compiled_graph.invoke(child_input)
        build_parent_update(child_output)
      end

      private

      def build_child_input(parent_state)
        if @input_map
          @input_map.each_with_object({}) do |(parent_key, child_key), input|
            input[child_key] = parent_state[parent_key]
          end
        else
          # Pass through all shared keys
          parent_state.dup
        end
      end

      def build_parent_update(child_output)
        if @output_map
          @output_map.each_with_object({}) do |(child_key, parent_key), update|
            update[parent_key] = child_output[child_key]
          end
        else
          child_output
        end
      end
    end
  end
end
