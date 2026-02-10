# frozen_string_literal: true

module LangraphRuby
  module Adapters
    class AnthropicAdapter < BaseAdapter
      DEFAULT_MODEL = "claude-sonnet-4-20250514"

      def initialize(client: nil, api_key: nil)
        @client = client || create_client(api_key)
      end

      def chat(messages:, tools: [], **config)
        formatted = format_messages(messages)
        system_prompt = extract_system_prompt(messages)

        params = {
          model: config[:model] || DEFAULT_MODEL,
          max_tokens: config[:max_tokens] || 4096,
          messages: formatted
        }
        params[:system] = system_prompt if system_prompt
        params[:tools] = format_tools(tools) if tools.any?
        params[:temperature] = config[:temperature] if config[:temperature]

        response = @client.messages.create(**params)
        parse_response(response)
      end

      private

      def create_client(api_key)
        require "anthropic"
        if api_key
          Anthropic::Client.new(api_key: api_key)
        else
          Anthropic::Client.new
        end
      end

      def extract_system_prompt(messages)
        sys = messages.select { |m| m.is_a?(Messages::SystemMessage) }
        return nil if sys.empty?

        sys.map(&:content).join("\n\n")
      end

      def format_messages(messages)
        messages.filter_map do |msg|
          case msg
          when Messages::SystemMessage
            nil # handled separately via system param
          when Messages::HumanMessage
            { role: "user", content: msg.content }
          when Messages::AIMessage
            format_ai_message(msg)
          when Messages::ToolMessage
            {
              role: "user",
              content: [{
                type: "tool_result",
                tool_use_id: msg.tool_call_id,
                content: msg.content
              }]
            }
          end
        end
      end

      def format_ai_message(msg)
        content = []
        content << { type: "text", text: msg.content } unless msg.content.empty?
        msg.tool_calls.each do |tc|
          content << { type: "tool_use", id: tc.id, name: tc.name, input: tc.args }
        end
        { role: "assistant", content: content }
      end

      def format_tools(tools)
        tools.map do |tool|
          schema = tool.to_schema
          {
            name: schema[:name],
            description: tool.description,
            input_schema: schema[:parameters]
          }
        end
      end

      def parse_response(response)
        content_text = ""
        tool_calls = []

        response.content.each do |block|
          case block.type
          when "text"
            content_text += block.text
          when "tool_use"
            tool_calls << Messages::ToolCall.new(
              id: block.id,
              name: block.name,
              args: block.input.is_a?(Hash) ? block.input : {}
            )
          end
        end

        Messages::AIMessage.new(
          content: content_text,
          tool_calls: tool_calls,
          metadata: {
            model: response.model,
            stop_reason: response.stop_reason,
            usage: {
              input_tokens: response.usage&.input_tokens,
              output_tokens: response.usage&.output_tokens
            }
          }
        )
      end
    end
  end
end
