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
        thread_id = config[:thread_id]
        resume_value = config[:resume]
        checkpoint_id = config[:checkpoint_id]

        # Resume from checkpoint or start fresh
        state, current_nodes, step, resumed_node = restore_or_init(
          input, thread_id, checkpoint_id, resume_value
        )

        # If resuming an interrupted node, execute it first with the resume value
        if resumed_node
          state, current_nodes, step = execute_resumed_node(
            resumed_node, state, step, resume_value, thread_id
          )
        end

        while current_nodes.any? && step < max_steps
          step += 1
          next_nodes = []

          current_nodes.each do |node_name|
            node_fn = @graph.nodes[node_name]
            raise GraphExecutionError, "Node '#{node_name}' not found" unless node_fn

            # interrupt_before check
            if @interrupt_before.include?(node_name)
              save_interrupt_checkpoint(thread_id, state, node_name, step, :before)
              return build_interrupt_result(state, node_name, step, :before)
            end

            result = execute_node_with_retry(node_fn, state, node_name, step, thread_id)
            return result if result.is_a?(InterruptResult)

            # Handle different return types
            state, resolved = process_node_result(result, state, node_name)

            # interrupt_after check
            if @interrupt_after.include?(node_name)
              save_interrupt_checkpoint(thread_id, state, node_name, step, :after, resolved)
              return build_interrupt_result(state, node_name, step, :after)
            end

            next_nodes.concat(resolved)
          end

          current_nodes = next_nodes.uniq
          current_nodes.reject! { |n| n == LangraphRuby::END_ }

          save_checkpoint(thread_id, state, current_nodes, step) if @checkpointer && thread_id
        end

        if step >= max_steps && current_nodes.any?
          raise MaxStepsReachedError, "Graph execution exceeded #{max_steps} steps"
        end

        save_checkpoint(thread_id, state, [], step) if @checkpointer && thread_id
        state
      end

      def stream(input, config: {}, stream_mode: :values)
        max_steps = config.fetch(:max_steps, DEFAULT_MAX_STEPS)
        thread_id = config[:thread_id]

        Enumerator.new do |yielder|
          state, current_nodes, step, _resumed = restore_or_init(input, thread_id, nil, nil)

          if stream_mode == :values
            yielder << State::StateSnapshot.new(values: state, next_nodes: current_nodes, step: step)
          end

          while current_nodes.any? && step < max_steps
            step += 1

            current_nodes.each do |node_name|
              node_fn = @graph.nodes[node_name]
              raise GraphExecutionError, "Node '#{node_name}' not found" unless node_fn

              result = execute_node(node_fn, state)
              state, _resolved = process_node_result(result, state, node_name)

              update = result.is_a?(Command) ? result.update : result
              if update.is_a?(Hash) && stream_mode == :updates
                yielder << { node: node_name, update: update, step: step }
              end
            end

            next_nodes = current_nodes.flat_map { |n| resolve_next_nodes(n, state) }.uniq
            next_nodes.reject! { |n| n == LangraphRuby::END_ }
            current_nodes = next_nodes

            save_checkpoint(thread_id, state, current_nodes, step) if @checkpointer && thread_id

            if stream_mode == :values
              yielder << State::StateSnapshot.new(values: state, next_nodes: current_nodes, step: step)
            end
          end

          if step >= max_steps && current_nodes.any?
            raise MaxStepsReachedError, "Graph execution exceeded #{max_steps} steps"
          end
        end
      end

      # Get the current state for a thread
      def get_state(config)
        thread_id = config[:thread_id]
        raise ArgumentError, "thread_id required" unless thread_id
        raise ArgumentError, "checkpointer required" unless @checkpointer

        checkpoint = @checkpointer.load(thread_id)
        return nil unless checkpoint

        State::StateSnapshot.new(
          values: checkpoint.state,
          next_nodes: checkpoint.next_nodes,
          step: checkpoint.step
        )
      end

      # Get the full state history for a thread
      def get_state_history(config)
        thread_id = config[:thread_id]
        raise ArgumentError, "thread_id required" unless thread_id
        raise ArgumentError, "checkpointer required" unless @checkpointer

        @checkpointer.list(thread_id).map do |checkpoint|
          State::StateSnapshot.new(
            values: checkpoint.state,
            next_nodes: checkpoint.next_nodes,
            step: checkpoint.step
          )
        end
      end

      # Manually update state for a thread
      def update_state(updates, config)
        thread_id = config[:thread_id]
        raise ArgumentError, "thread_id required" unless thread_id
        raise ArgumentError, "checkpointer required" unless @checkpointer

        checkpoint = @checkpointer.load(thread_id)
        raise InvalidStateError, "No checkpoint found for thread '#{thread_id}'" unless checkpoint

        new_state = apply_state_update(checkpoint.state, updates)
        save_checkpoint(thread_id, new_state, checkpoint.next_nodes, checkpoint.step + 1)
        new_state
      end

      private

      def restore_or_init(input, thread_id, checkpoint_id, resume_value)
        resumed_node = nil

        if @checkpointer && thread_id
          checkpoint = if checkpoint_id
                         @checkpointer.load_by_id(thread_id, checkpoint_id)
                       else
                         @checkpointer.load(thread_id)
                       end

          if checkpoint
            if checkpoint.interrupted? && resume_value != nil
              # Resuming from an interrupt
              resumed_node = checkpoint.interrupted_node
              state = checkpoint.state.dup
              next_nodes = checkpoint.next_nodes
              step = checkpoint.step
              return [state, next_nodes, step, resumed_node]
            elsif checkpoint.interrupted?
              # Re-invoking a thread that's interrupted without resume — return interrupt
              # Let caller handle
              state = checkpoint.state.dup
              next_nodes = checkpoint.next_nodes
              step = checkpoint.step
              return [state, next_nodes, step, nil]
            else
              # Normal continuation from last checkpoint
              state = checkpoint.state.dup
              next_nodes = checkpoint.next_nodes
              step = checkpoint.step
              if input.is_a?(Hash) && input.any?
                state = apply_state_update(state, input)
                next_nodes = resolve_start_nodes(state)
                step = checkpoint.step
              end
              return [state, next_nodes, step, nil]
            end
          end
        end

        state = initialize_state(input)
        current_nodes = resolve_start_nodes(state)
        [state, current_nodes, 0, resumed_node]
      end

      def execute_resumed_node(node_name, state, step, resume_value, thread_id)
        node_fn = @graph.nodes[node_name]
        raise GraphExecutionError, "Resumed node '#{node_name}' not found" unless node_fn

        step += 1

        # Execute the node; if it calls LangraphRuby.interrupt, the resume_value
        # is injected via the state under :__resume_value__
        state_with_resume = state.merge(__resume_value__: resume_value)
        update = execute_node(node_fn, state_with_resume)
        state = apply_state_update(state, update) if update.is_a?(Hash)

        next_nodes = resolve_next_nodes(node_name, state)
        next_nodes.reject! { |n| n == LangraphRuby::END_ }

        save_checkpoint(thread_id, state, next_nodes, step) if @checkpointer && thread_id

        [state, next_nodes, step]
      end

      def execute_node_with_retry(node_fn, state, node_name, step, thread_id)
        retry_policy = @graph.respond_to?(:retry_policies) && @graph.retry_policies[node_name]

        executor = -> {
          node_fn.call(state)
        }

        result = if retry_policy
                   retry_policy.execute(&executor)
                 else
                   executor.call
                 end

        result
      rescue GraphInterrupt => e
        save_interrupt_checkpoint(thread_id, state, node_name, step, :dynamic, [], e.value)
        build_interrupt_result(state, node_name, step, :dynamic, e.value)
      rescue StandardError => e
        raise GraphExecutionError, "Node execution failed: #{e.message}"
      end

      # Process the return value of a node: Hash, Command, Array<Send>, or nil
      def process_node_result(result, state, node_name)
        case result
        when Command
          state = apply_state_update(state, result.update) if result.update.is_a?(Hash) && result.update.any?
          resolved = result.goto
          [state, resolved]
        when Array
          # Array of Send objects for fan-out
          if result.all? { |r| r.is_a?(Send) }
            result.each do |send_obj|
              target_fn = @graph.nodes[send_obj.node]
              raise GraphExecutionError, "Send target '#{send_obj.node}' not found" unless target_fn

              merged = state.merge(send_obj.state.transform_keys(&:to_sym))
              update = execute_node(target_fn, merged)
              state = apply_state_update(state, update) if update.is_a?(Hash)
            end
            # After all sends, resolve next from the originating node
            resolved = resolve_next_nodes(node_name, state)
            [state, resolved]
          else
            # Regular array return — not a Send array, ignore
            [state, resolve_next_nodes(node_name, state)]
          end
        when Hash
          state = apply_state_update(state, result)
          resolved = resolve_next_nodes(node_name, state)
          [state, resolved]
        else
          [state, resolve_next_nodes(node_name, state)]
        end
      end

      def build_interrupt_result(state, node_name, step, kind, value = nil)
        InterruptResult.new(
          state: state,
          interrupted_node: node_name,
          interrupt_kind: kind,
          interrupt_value: value,
          step: step
        )
      end

      def save_checkpoint(thread_id, state, next_nodes, step, parent_id: nil)
        return unless @checkpointer && thread_id

        parent = @checkpointer.load(thread_id)
        checkpoint = Checkpointers::Checkpoint.new(
          thread_id: thread_id,
          state: deep_dup_state(state),
          next_nodes: next_nodes,
          step: step,
          parent_id: parent&.id
        )
        @checkpointer.save(checkpoint)
      end

      def save_interrupt_checkpoint(thread_id, state, node_name, step, kind, next_nodes = [], value = nil)
        return unless @checkpointer && thread_id

        parent = @checkpointer.load(thread_id)

        # For interrupt_before, the next node to run is the interrupted node itself
        effective_next = kind == :before ? [node_name] : next_nodes

        checkpoint = Checkpointers::Checkpoint.new(
          thread_id: thread_id,
          state: deep_dup_state(state),
          next_nodes: effective_next,
          step: step,
          parent_id: parent&.id,
          interrupted_node: node_name,
          interrupt_value: value,
          metadata: { interrupt_kind: kind.to_s }
        )
        @checkpointer.save(checkpoint)
      end

      def deep_dup_state(state)
        state.each_with_object({}) do |(k, v), h|
          h[k] = v.is_a?(Array) ? v.dup : v
        end
      end

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
      rescue GraphInterrupt
        raise
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
          result = result.is_a?(Array) ? result.map(&:to_sym) : [result.to_sym]
          result
        end
      end
    end

    # Returned when execution is interrupted
    class InterruptResult
      attr_reader :state, :interrupted_node, :interrupt_kind, :interrupt_value, :step

      def initialize(state:, interrupted_node:, interrupt_kind:, interrupt_value: nil, step: 0)
        @state = state
        @interrupted_node = interrupted_node
        @interrupt_kind = interrupt_kind
        @interrupt_value = interrupt_value
        @step = step
      end

      def interrupted?
        true
      end

      def [](key)
        @state[key.to_sym]
      end
    end
  end
end
