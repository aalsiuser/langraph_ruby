# frozen_string_literal: true

module LangraphRuby
  module Agents
    class ReactAgent
      class AgentState < State::StateSchema
        field :messages, type: Array, reducer: :add_messages
      end

      # Creates a compiled ReAct agent graph
      #
      # @param adapter [Adapters::BaseAdapter] LLM adapter instance
      # @param tools [Array<Tools::Tool>] Available tools
      # @param system_prompt [String, nil] System instructions for the agent
      # @param max_steps [Integer] Maximum execution steps (default 25); becomes the
      #   compiled graph's default and can still be overridden per-invoke via
      #   `config: { max_steps: N }`
      # @param model_config [Hash] Options forwarded to every adapter.chat call
      #   (e.g. model:, temperature:, max_tokens:)
      # @return [Execution::CompiledGraph]
      def self.create(adapter:, tools:, system_prompt: nil, max_steps: 25, state_schema: nil,
                      model_config: {})
        schema = state_schema || AgentState
        tool_node = Tools::ToolNode.new(tools: tools, handle_errors: true)

        agent_node = ->(state) {
          msgs = state[:messages].dup
          if system_prompt && msgs.none? { |m| m.is_a?(Messages::SystemMessage) }
            msgs.unshift(Messages::SystemMessage.new(content: system_prompt))
          end

          ai_message = adapter.chat(messages: msgs, tools: tools, **model_config)
          { messages: [ai_message] }
        }

        should_continue = ->(state) {
          last_msg = state[:messages].last
          if last_msg.is_a?(Messages::AIMessage) && last_msg.has_tool_calls?
            :tools
          else
            LangraphRuby::END_
          end
        }

        graph = Graph::StateGraph.new(schema)
        graph.add_node(:agent, agent_node)
        graph.add_node(:tools, tool_node)
        graph.add_edge(LangraphRuby::START, :agent)
        graph.add_conditional_edges(:agent, should_continue)
        graph.add_edge(:tools, :agent)

        graph.compile(default_max_steps: max_steps)
      end
    end
  end
end
