# frozen_string_literal: true

module LangraphRuby
  module Messages
    class RemoveMessage
      attr_reader :id

      def initialize(id:)
        @id = id
      end
    end
  end
end
