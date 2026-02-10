# frozen_string_literal: true

require "test_helper"

class StateSchemaTest < Minitest::Test
  def setup
    @schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
      field :count, type: Integer, default: 0, reducer: :add
      field :status, type: String, default: "idle"
      field :metadata, type: Hash, reducer: :merge
    end
  end

  def test_build_initial_state
    state = @schema.build_initial_state
    assert_equal [], state[:messages]
    assert_equal 0, state[:count]
    assert_equal "idle", state[:status]
    assert_equal({}, state[:metadata])
  end

  def test_apply_update_with_reducer
    state = @schema.build_initial_state
    msg = LangraphRuby::Messages::HumanMessage.new(content: "hi")
    updated = @schema.apply_update(state, { messages: [msg], count: 1 })
    assert_equal 1, updated[:messages].length
    assert_equal 1, updated[:count]
  end

  def test_apply_update_without_reducer_overwrites
    state = @schema.build_initial_state
    updated = @schema.apply_update(state, { status: "running" })
    assert_equal "running", updated[:status]
  end

  def test_apply_update_ignores_unknown_fields
    state = @schema.build_initial_state
    updated = @schema.apply_update(state, { unknown_field: "value" })
    assert_nil updated[:unknown_field]
  end

  def test_apply_update_does_not_mutate_original
    state = @schema.build_initial_state
    @schema.apply_update(state, { status: "done" })
    assert_equal "idle", state[:status]
  end

  def test_field_with_callable_default
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :items, default: -> { [1, 2, 3] }
    end
    state = schema.build_initial_state
    assert_equal [1, 2, 3], state[:items]
  end

  def test_field_with_custom_lambda_reducer
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :values, type: Array, reducer: ->(old, new_val) { (old || []) | Array(new_val) }
    end
    state = schema.build_initial_state
    updated = schema.apply_update(state, { values: [1, 2] })
    updated = schema.apply_update(updated, { values: [2, 3] })
    assert_equal [1, 2, 3], updated[:values]
  end

  def test_inherited_schema
    parent = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
    end
    child = Class.new(parent) do
      field :extra, type: String, default: "yes"
    end
    state = child.build_initial_state
    assert_equal [], state[:messages]
    assert_equal "yes", state[:extra]
  end
end
