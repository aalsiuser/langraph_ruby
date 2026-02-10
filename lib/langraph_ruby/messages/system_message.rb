# frozen_string_literal: true

module LangraphRuby
  module Messages
    class SystemMessage < BaseMessage
      def initialize(content:, id: nil, metadata: {})
        super(content: content, type: "system", id: id, metadata: metadata)
      end
    end
  end
end
