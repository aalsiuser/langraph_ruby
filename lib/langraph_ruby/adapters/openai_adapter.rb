# frozen_string_literal: true

module LangraphRuby
  module Adapters
    class OpenAiAdapter < BaseAdapter
      DEFAULT_MODEL = "gpt-4o"

      def initialize(client: nil, api_key: nil)
        @client = client || create_client(api_key)
      end

      # @param on_token [#call, nil] when given (via config), the response is
      #   streamed and each content-delta string is yielded to it as it arrives.
      #   The assembled AIMessage (with tool_calls and usage) is still returned,
      #   so callers get the same result whether or not they stream.
      def chat(messages:, tools: [], **config)
        formatted = format_messages(messages)

        params = {
          model: config[:model] || DEFAULT_MODEL,
          messages: formatted
        }
        params[:tools] = format_tools(tools) if tools.any?
        params[:temperature] = config[:temperature] if config[:temperature]
        params[:max_tokens] = config[:max_tokens] if config[:max_tokens]

        return stream_chat(params, config[:on_token]) if config[:on_token]

        response = @client.chat(parameters: params)
        parse_response(response)
      end

      private

      # Streams the completion, forwarding content tokens to on_token, and
      # rebuilds the full AIMessage (content + tool_calls + usage) from the
      # accumulated chunks. Tool-call arguments arrive fragmented across chunks
      # and are stitched back together by index.
      def stream_chat(params, on_token)
        content = +""
        tool_fragments = {}
        meta = {}

        params[:stream] = proc do |chunk, _bytesize = nil|
          if (choice = chunk.dig("choices", 0))
            delta = choice["delta"] || {}

            if (text = delta["content"])
              content << text
              on_token.call(text)
            end

            Array(delta["tool_calls"]).each do |tc|
              frag = (tool_fragments[tc["index"]] ||= { "id" => nil, "name" => nil, "args" => +"" })
              frag["id"] ||= tc["id"]
              if (fn = tc["function"])
                frag["name"] ||= fn["name"]
                frag["args"] << fn["arguments"].to_s if fn["arguments"]
              end
            end

            meta[:finish_reason] = choice["finish_reason"] if choice["finish_reason"]
          end

          meta[:usage] = chunk["usage"] if chunk["usage"]
          meta[:model] ||= chunk["model"]
        end
        params[:stream_options] = { include_usage: true }

        @client.chat(parameters: params)

        tool_calls = tool_fragments.values.map do |frag|
          args = frag["args"].to_s
          parsed = args.empty? ? {} : safe_parse(args)
          Messages::ToolCall.new(id: frag["id"], name: frag["name"], args: parsed)
        end

        Messages::AIMessage.new(
          content: content,
          tool_calls: tool_calls,
          metadata: { model: meta[:model], finish_reason: meta[:finish_reason], usage: meta[:usage] }
        )
      end

      def safe_parse(json)
        JSON.parse(json)
      rescue JSON::ParserError
        {}
      end

      def create_client(api_key)
        require "openai"
        OpenAI::Client.new(access_token: api_key || ENV["OPENAI_API_KEY"])
      end

      def format_messages(messages)
        messages.map do |msg|
          case msg
          when Messages::SystemMessage
            { role: "system", content: msg.content }
          when Messages::HumanMessage
            { role: "user", content: msg.content }
          when Messages::AIMessage
            format_ai_message(msg)
          when Messages::ToolMessage
            {
              role: "tool",
              tool_call_id: msg.tool_call_id,
              content: msg.content
            }
          end
        end
      end

      def format_ai_message(msg)
        result = { role: "assistant" }
        result[:content] = msg.content unless msg.content.empty?

        if msg.has_tool_calls?
          result[:tool_calls] = msg.tool_calls.map do |tc|
            {
              id: tc.id,
              type: "function",
              function: { name: tc.name, arguments: (tc.args || {}).to_json }
            }
          end
        end

        result
      end

      def format_tools(tools)
        tools.map do |tool|
          schema = tool.to_schema
          {
            type: "function",
            function: {
              name: schema[:name],
              description: tool.description,
              parameters: schema[:parameters]
            }
          }
        end
      end

      def parse_response(response)
        choice = response.dig("choices", 0)
        message = choice&.dig("message") || {}

        content = message["content"] || ""
        tool_calls = (message["tool_calls"] || []).map do |tc|
          args = tc.dig("function", "arguments")
          parsed_args = args.is_a?(String) ? JSON.parse(args) : (args || {})

          Messages::ToolCall.new(
            id: tc["id"],
            name: tc.dig("function", "name"),
            args: parsed_args
          )
        end

        Messages::AIMessage.new(
          content: content,
          tool_calls: tool_calls,
          metadata: {
            model: response["model"],
            finish_reason: choice&.dig("finish_reason"),
            usage: response["usage"]
          }
        )
      end
    end
  end
end
