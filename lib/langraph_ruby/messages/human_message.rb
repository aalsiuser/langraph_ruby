# frozen_string_literal: true

module LangraphRuby
  module Messages
    class HumanMessage < BaseMessage
      def initialize(content:, id: nil, metadata: {})
        super(content: content, type: "human", id: id, metadata: metadata)
      end
    end
  end
end
