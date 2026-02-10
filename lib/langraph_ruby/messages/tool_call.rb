# frozen_string_literal: true

require "securerandom"

module LangraphRuby
  module Messages
    class ToolCall
      attr_reader :id, :name, :args

      def initialize(name:, args: {}, id: nil)
        @id = id || SecureRandom.uuid
        @name = name
        @args = args
      end

      def to_h
        { id: @id, name: @name, args: @args }
      end

      def ==(other)
        other.is_a?(ToolCall) && @id == other.id
      end
    end
  end
end
