# frozen_string_literal: true

module LangraphRuby
  module Adapters
    class RubyLlmAdapter < BaseAdapter
      DEFAULT_MODEL = "claude-sonnet-4-20250514"

      def initialize(model: nil)
        require "ruby_llm"
        @model = model || DEFAULT_MODEL
        @chat = nil
      end

      def chat(messages:, tools: [], **config)
        model = config[:model] || @model
        chat_instance = build_chat(model, tools, config)

        # RubyLLM expects the last user message to be passed to ask()
        # and prior messages set up as conversation context
        setup_messages = messages[0...-1]
        last_message = messages.last

        setup_messages.each do |msg|
          case msg
          when Messages::SystemMessage
            chat_instance.with_instructions(msg.content)
          when Messages::HumanMessage
            chat_instance.add_message(role: :user, content: msg.content)
          when Messages::AIMessage
            chat_instance.add_message(role: :assistant, content: msg.content)
          when Messages::ToolMessage
            chat_instance.add_message(role: :tool, content: msg.content, tool_call_id: msg.tool_call_id)
          end
        end

        response = chat_instance.ask(last_message.content)
        parse_response(response)
      end

      private

      def build_chat(model, tools, config)
        chat = RubyLLM.chat(model: model)
        chat.with_temperature(config[:temperature]) if config[:temperature]

        tools.each do |tool|
          chat.with_tool(build_ruby_llm_tool(tool))
        end

        chat
      end

      def build_ruby_llm_tool(tool)
        tool_name = tool.name
        tool_desc = tool.description
        tool_params = tool.parameters
        tool_fn = tool.method(:call)

        Class.new(RubyLLM::Tool) do
          define_method(:name) { tool_name }
          define_method(:description) { tool_desc }

          tool_params.each do |param_name, param_def|
            parameter param_name.to_sym,
                      type: param_def[:type] || "string",
                      desc: param_def[:description] || "",
                      required: param_def[:required] || false
          end

          define_method(:execute) do |**args|
            tool_fn.call(args)
          end
        end
      end

      def parse_response(response)
        if response.is_a?(RubyLLM::Message)
          tool_calls = (response.tool_calls || {}).map do |id, tc|
            Messages::ToolCall.new(
              id: id,
              name: tc.name,
              args: tc.arguments || {}
            )
          end

          Messages::AIMessage.new(
            content: response.content || "",
            tool_calls: tool_calls,
            metadata: {
              model: response.model_id,
              input_tokens: response.input_tokens,
              output_tokens: response.output_tokens
            }
          )
        else
          Messages::AIMessage.new(content: response.to_s)
        end
      end
    end
  end
end
