# frozen_string_literal: true

module LangraphRuby
  module Tools
    class ToolNode
      # @param tools [Array<Tool>] List of available tools
      # @param handle_errors [Boolean, Proc] Error handling strategy:
      #   - true: return error as ToolMessage content
      #   - false: raise the error (default)
      #   - Proc: custom handler receiving (error, tool_call) returning string
      def initialize(tools:, handle_errors: false)
        @tools = tools.each_with_object({}) { |t, h| h[t.name] = t }
        @handle_errors = handle_errors
      end

      # Callable interface for use as a graph node
      # Looks at the last AIMessage's tool_calls and executes each
      def call(state)
        messages = state[:messages] || []
        last_ai = messages.reverse.find { |m| m.is_a?(Messages::AIMessage) }

        unless last_ai&.has_tool_calls?
          return { messages: [] }
        end

        tool_messages = last_ai.tool_calls.map do |tool_call|
          execute_tool_call(tool_call)
        end

        { messages: tool_messages }
      end

      def available_tool_names
        @tools.keys
      end

      private

      def execute_tool_call(tool_call)
        tool = @tools[tool_call.name]

        unless tool
          return handle_tool_error(
            ToolNotFoundError.new("Tool '#{tool_call.name}' not found. Available: #{@tools.keys.join(', ')}"),
            tool_call
          )
        end

        result = tool.call(tool_call.args)

        Messages::ToolMessage.new(
          content: result.to_s,
          tool_call_id: tool_call.id,
          tool_name: tool_call.name
        )
      rescue ToolNotFoundError
        raise
      rescue StandardError => e
        handle_tool_error(e, tool_call)
      end

      def handle_tool_error(error, tool_call)
        case @handle_errors
        when true
          Messages::ToolMessage.new(
            content: "Error: #{error.message}",
            tool_call_id: tool_call.id,
            tool_name: tool_call.name
          )
        when Proc
          content = @handle_errors.call(error, tool_call)
          Messages::ToolMessage.new(
            content: content.to_s,
            tool_call_id: tool_call.id,
            tool_name: tool_call.name
          )
        else
          raise GraphExecutionError, "Tool '#{tool_call.name}' failed: #{error.message}"
        end
      end
    end

    class ToolNotFoundError < LangraphRuby::Error; end
  end
end
