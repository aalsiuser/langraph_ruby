# frozen_string_literal: true

module LangraphRuby
  module Adapters
    class BaseAdapter
      # @param messages [Array<Messages::BaseMessage>] Conversation messages
      # @param tools [Array<Tools::Tool>] Available tools
      # @param config [Hash] Provider-specific config (model, temperature, etc.)
      # @return [Messages::AIMessage] The LLM response
      def chat(messages:, tools: [], **config)
        raise NotImplementedError, "#{self.class}#chat must be implemented"
      end

      private

      # Convert LangraphRuby messages to provider-specific format
      def format_messages(messages)
        raise NotImplementedError
      end

      # Convert LangraphRuby tools to provider-specific format
      def format_tools(tools)
        raise NotImplementedError
      end

      # Convert provider response to LangraphRuby AIMessage
      def parse_response(response)
        raise NotImplementedError
      end
    end
  end
end
