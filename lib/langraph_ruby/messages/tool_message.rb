# frozen_string_literal: true

module LangraphRuby
  module Messages
    class ToolMessage < BaseMessage
      attr_reader :tool_call_id, :tool_name

      def initialize(content:, tool_call_id:, tool_name:, id: nil, metadata: {})
        super(content: content, type: "tool", id: id, metadata: metadata)
        @tool_call_id = tool_call_id
        @tool_name = tool_name
      end

      def to_h
        super.merge(tool_call_id: @tool_call_id, tool_name: @tool_name)
      end
    end
  end
end
