# frozen_string_literal: true

module LangraphRuby
  module Messages
    class AIMessage < BaseMessage
      attr_reader :tool_calls

      def initialize(content:, tool_calls: [], id: nil, metadata: {})
        super(content: content, type: "ai", id: id, metadata: metadata)
        @tool_calls = tool_calls
      end

      def has_tool_calls?
        !@tool_calls.empty?
      end

      def to_h
        super.merge(tool_calls: @tool_calls.map(&:to_h))
      end
    end
  end
end
