# frozen_string_literal: true

module LangraphRuby
  module State
    module Reducers
      # Overwrites the old value with the new value (default behavior)
      LAST_VALUE = ->(old_val, new_val) { new_val }

      # Appends new values to an existing array
      APPEND = ->(old_val, new_val) {
        old_arr = old_val.is_a?(Array) ? old_val : []
        new_arr = new_val.is_a?(Array) ? new_val : [new_val]
        old_arr + new_arr
      }

      # Smart message list reducer:
      # - Appends new messages
      # - Updates existing messages by ID
      # - Removes messages via RemoveMessage
      ADD_MESSAGES = ->(old_val, new_val) {
        existing = (old_val.is_a?(Array) ? old_val : []).dup
        updates = new_val.is_a?(Array) ? new_val : [new_val]

        updates.each do |msg|
          case msg
          when LangraphRuby::Messages::RemoveMessage
            existing.reject! { |m| m.id == msg.id }
          when LangraphRuby::Messages::BaseMessage
            idx = existing.index { |m| m.id == msg.id }
            if idx
              existing[idx] = msg
            else
              existing << msg
            end
          end
        end

        existing
      }

      # Sums numeric values
      ADD = ->(old_val, new_val) {
        (old_val || 0) + (new_val || 0)
      }

      # Merges hashes
      MERGE = ->(old_val, new_val) {
        old_h = old_val.is_a?(Hash) ? old_val : {}
        new_h = new_val.is_a?(Hash) ? new_val : {}
        old_h.merge(new_h)
      }
    end
  end
end
