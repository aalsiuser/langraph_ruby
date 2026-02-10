# frozen_string_literal: true

module LangraphRuby
  module Execution
    class CompiledGraph
      DEFAULT_MAX_STEPS = 25

      attr_reader :graph

      def initialize(graph:, checkpointer: nil, interrupt_before: [], interrupt_after: [])
        @graph = graph
        @checkpointer = checkpointer
        @interrupt_before = interrupt_before
        @interrupt_after = interrupt_after
      end

      def invoke(input, config: {})
        max_steps = config.fetch(:max_steps, DEFAULT_MAX_STEPS)
        state = initialize_state(input)
        current_nodes = resolve_start_nodes(state)
        step = 0

        while current_nodes.any? && step < max_steps
          step += 1
          next_nodes = []

          current_nodes.each do |node_name|
            node_fn = @graph.nodes[node_name]
            raise GraphExecutionError, "Node '#{node_name}' not found" unless node_fn

            update = execute_node(node_fn, state)
            state = apply_state_update(state, update) if update.is_a?(Hash)

            resolved = resolve_next_nodes(node_name, state)
            next_nodes.concat(resolved)
          end

          current_nodes = next_nodes.uniq
          current_nodes.reject! { |n| n == LangraphRuby::END_ }
        end

        if step >= max_steps && current_nodes.any?
          raise MaxStepsReachedError, "Graph execution exceeded #{max_steps} steps"
        end

        state
      end

      def stream(input, config: {}, stream_mode: :values)
        max_steps = config.fetch(:max_steps, DEFAULT_MAX_STEPS)

        Enumerator.new do |yielder|
          state = initialize_state(input)
          current_nodes = resolve_start_nodes(state)
          step = 0

          if stream_mode == :values
            yielder << State::StateSnapshot.new(values: state, next_nodes: current_nodes, step: step)
          end

          while current_nodes.any? && step < max_steps
            step += 1

            current_nodes.each do |node_name|
              node_fn = @graph.nodes[node_name]
              raise GraphExecutionError, "Node '#{node_name}' not found" unless node_fn

              update = execute_node(node_fn, state)

              if update.is_a?(Hash)
                state = apply_state_update(state, update)

                if stream_mode == :updates
                  yielder << { node: node_name, update: update, step: step }
                end
              end
            end

            next_nodes = current_nodes.flat_map { |n| resolve_next_nodes(n, state) }.uniq
            next_nodes.reject! { |n| n == LangraphRuby::END_ }
            current_nodes = next_nodes

            if stream_mode == :values
              yielder << State::StateSnapshot.new(values: state, next_nodes: current_nodes, step: step)
            end
          end

          if step >= max_steps && current_nodes.any?
            raise MaxStepsReachedError, "Graph execution exceeded #{max_steps} steps"
          end
        end
      end

      private

      def initialize_state(input)
        state = if @graph.schema
                  @graph.schema.build_initial_state
                else
                  {}
                end

        if input.is_a?(Hash)
          input.each do |key, value|
            key = key.to_sym
            state[key] = value
          end
        end

        state
      end

      def execute_node(node_fn, state)
        node_fn.call(state)
      rescue StandardError => e
        raise GraphExecutionError, "Node execution failed: #{e.message}"
      end

      def apply_state_update(state, update)
        if @graph.schema
          @graph.schema.apply_update(state, update)
        else
          state.merge(update.transform_keys(&:to_sym))
        end
      end

      def resolve_start_nodes(state)
        if @graph.edges[LangraphRuby::START]
          [@graph.edges[LangraphRuby::START]]
        elsif @graph.conditional_edges[LangraphRuby::START]
          resolve_conditional(LangraphRuby::START, state)
        else
          raise GraphExecutionError, "No edge from START"
        end
      end

      def resolve_next_nodes(node_name, state)
        if @graph.edges[node_name]
          target = @graph.edges[node_name]
          [target]
        elsif @graph.conditional_edges[node_name]
          resolve_conditional(node_name, state)
        else
          [LangraphRuby::END_]
        end
      end

      def resolve_conditional(node_name, state)
        cond_config = @graph.conditional_edges[node_name]
        result = cond_config[:condition].call(state)

        if cond_config[:mapping]
          target = cond_config[:mapping][result.to_sym]
          raise GraphExecutionError, "Conditional edge from '#{node_name}' returned unmapped value: #{result.inspect}" unless target
          [target]
        else
          # Result is the node name directly
          result = result.is_a?(Array) ? result.map(&:to_sym) : [result.to_sym]
          result
        end
      end
    end
  end
end
