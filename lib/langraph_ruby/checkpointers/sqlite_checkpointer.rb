# frozen_string_literal: true

require "json"
require "time"

module LangraphRuby
  module Checkpointers
    class SqliteCheckpointer < BaseCheckpointer
      def initialize(db_path: ":memory:")
        require "sqlite3"
        @db = SQLite3::Database.new(db_path)
        @db.results_as_hash = true
        create_table
      end

      def save(checkpoint)
        @db.execute(
          <<~SQL,
            INSERT INTO checkpoints
              (id, thread_id, parent_id, state, next_nodes, step,
               metadata, interrupted_node, interrupt_value, pending_writes, created_at)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
          SQL
          [
            checkpoint.id,
            checkpoint.thread_id,
            checkpoint.parent_id,
            serialize_state(checkpoint.state),
            JSON.generate(checkpoint.next_nodes.map(&:to_s)),
            checkpoint.step,
            JSON.generate(checkpoint.metadata),
            checkpoint.interrupted_node&.to_s,
            checkpoint.interrupt_value.nil? ? nil : JSON.generate(checkpoint.interrupt_value),
            checkpoint.pending_writes.nil? ? nil : JSON.generate(checkpoint.pending_writes),
            checkpoint.created_at.iso8601
          ]
        )
        checkpoint
      end

      def load(thread_id)
        row = @db.get_first_row(
          "SELECT * FROM checkpoints WHERE thread_id = ? ORDER BY step DESC, created_at DESC LIMIT 1",
          thread_id
        )
        return nil unless row

        row_to_checkpoint(row)
      end

      def load_by_id(thread_id, checkpoint_id)
        row = @db.get_first_row(
          "SELECT * FROM checkpoints WHERE thread_id = ? AND id = ?",
          [thread_id, checkpoint_id]
        )
        return nil unless row

        row_to_checkpoint(row)
      end

      def list(thread_id)
        rows = @db.execute(
          "SELECT * FROM checkpoints WHERE thread_id = ? ORDER BY step DESC, created_at DESC",
          thread_id
        )
        rows.map { |row| row_to_checkpoint(row) }
      end

      def delete(thread_id)
        @db.execute("DELETE FROM checkpoints WHERE thread_id = ?", thread_id)
      end

      def close
        @db.close
      end

      private

      def create_table
        @db.execute(<<~SQL)
          CREATE TABLE IF NOT EXISTS checkpoints (
            id TEXT PRIMARY KEY,
            thread_id TEXT NOT NULL,
            parent_id TEXT,
            state TEXT NOT NULL,
            next_nodes TEXT NOT NULL,
            step INTEGER NOT NULL,
            metadata TEXT,
            interrupted_node TEXT,
            interrupt_value TEXT,
            pending_writes TEXT,
            created_at TEXT NOT NULL
          )
        SQL
        @db.execute(<<~SQL)
          CREATE INDEX IF NOT EXISTS idx_checkpoints_thread
          ON checkpoints (thread_id, step DESC, created_at DESC)
        SQL
      end

      def serialize_state(state)
        serializable = state.transform_values do |v|
          case v
          when Array
            v.map { |item| item.respond_to?(:to_h) ? { "__class__" => item.class.name }.merge(item.to_h) : item }
          else
            v.respond_to?(:to_h) && v.is_a?(Messages::BaseMessage) ? { "__class__" => v.class.name }.merge(v.to_h) : v
          end
        end
        JSON.generate(serializable)
      end

      def deserialize_state(json_str)
        raw = JSON.parse(json_str)
        raw.each_with_object({}) do |(key, value), state|
          state[key.to_sym] = case value
                              when Array
                                value.map { |item| deserialize_value(item) }
                              else
                                deserialize_value(value)
                              end
        end
      end

      def deserialize_value(value)
        return value unless value.is_a?(Hash) && value["__class__"]

        klass_name = value["__class__"]
        case klass_name
        when "LangraphRuby::Messages::HumanMessage"
          Messages::HumanMessage.new(content: value["content"], id: value["id"])
        when "LangraphRuby::Messages::AIMessage"
          tool_calls = (value["tool_calls"] || []).map do |tc|
            Messages::ToolCall.new(name: tc["name"], args: tc["args"] || {}, id: tc["id"])
          end
          Messages::AIMessage.new(content: value["content"], id: value["id"], tool_calls: tool_calls)
        when "LangraphRuby::Messages::ToolMessage"
          Messages::ToolMessage.new(
            content: value["content"], id: value["id"],
            tool_call_id: value["tool_call_id"], tool_name: value["tool_name"]
          )
        when "LangraphRuby::Messages::SystemMessage"
          Messages::SystemMessage.new(content: value["content"], id: value["id"])
        else
          value
        end
      end

      def row_to_checkpoint(row)
        Checkpoint.new(
          id: row["id"],
          thread_id: row["thread_id"],
          parent_id: row["parent_id"],
          state: deserialize_state(row["state"]),
          next_nodes: JSON.parse(row["next_nodes"]).map(&:to_sym),
          step: row["step"],
          metadata: JSON.parse(row["metadata"] || "{}"),
          interrupted_node: row["interrupted_node"]&.to_sym,
          interrupt_value: row["interrupt_value"] ? JSON.parse(row["interrupt_value"]) : nil,
          pending_writes: row["pending_writes"] ? JSON.parse(row["pending_writes"]) : nil,
          created_at: Time.parse(row["created_at"])
        )
      end
    end
  end
end
