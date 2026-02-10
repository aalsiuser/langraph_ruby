# frozen_string_literal: true

require "securerandom"

module LangraphRuby
  module Messages
    class BaseMessage
      attr_reader :id, :content, :type, :metadata

      def initialize(content:, type:, id: nil, metadata: {})
        @id = id || SecureRandom.uuid
        @content = content
        @type = type.to_s
        @metadata = metadata
      end

      def to_h
        { id: @id, type: @type, content: @content, metadata: @metadata }
      end

      def ==(other)
        other.is_a?(BaseMessage) && @id == other.id
      end

      alias_method :eql?, :==

      def hash
        @id.hash
      end
    end
  end
end
