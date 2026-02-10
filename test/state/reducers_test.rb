# frozen_string_literal: true

require "test_helper"

class ReducersTest < Minitest::Test
  def test_last_value
    assert_equal "new", LangraphRuby::State::Reducers::LAST_VALUE.call("old", "new")
  end

  def test_append_arrays
    result = LangraphRuby::State::Reducers::APPEND.call([1, 2], [3, 4])
    assert_equal [1, 2, 3, 4], result
  end

  def test_append_single_to_array
    result = LangraphRuby::State::Reducers::APPEND.call([1], 2)
    assert_equal [1, 2], result
  end

  def test_append_to_nil
    result = LangraphRuby::State::Reducers::APPEND.call(nil, [1, 2])
    assert_equal [1, 2], result
  end

  def test_add_messages_appends_new
    msg1 = LangraphRuby::Messages::HumanMessage.new(content: "hi", id: "1")
    msg2 = LangraphRuby::Messages::AIMessage.new(content: "hello", id: "2")
    result = LangraphRuby::State::Reducers::ADD_MESSAGES.call([msg1], [msg2])
    assert_equal 2, result.length
    assert_equal "1", result[0].id
    assert_equal "2", result[1].id
  end

  def test_add_messages_updates_by_id
    msg1 = LangraphRuby::Messages::HumanMessage.new(content: "hi", id: "1")
    msg1_updated = LangraphRuby::Messages::HumanMessage.new(content: "hello", id: "1")
    result = LangraphRuby::State::Reducers::ADD_MESSAGES.call([msg1], [msg1_updated])
    assert_equal 1, result.length
    assert_equal "hello", result[0].content
  end

  def test_add_messages_removes_by_id
    msg1 = LangraphRuby::Messages::HumanMessage.new(content: "hi", id: "1")
    msg2 = LangraphRuby::Messages::AIMessage.new(content: "hey", id: "2")
    remove = LangraphRuby::Messages::RemoveMessage.new(id: "1")
    result = LangraphRuby::State::Reducers::ADD_MESSAGES.call([msg1, msg2], [remove])
    assert_equal 1, result.length
    assert_equal "2", result[0].id
  end

  def test_add_reducer
    assert_equal 7, LangraphRuby::State::Reducers::ADD.call(3, 4)
    assert_equal 5, LangraphRuby::State::Reducers::ADD.call(nil, 5)
  end

  def test_merge_reducer
    result = LangraphRuby::State::Reducers::MERGE.call({ a: 1 }, { b: 2 })
    assert_equal({ a: 1, b: 2 }, result)
  end

  def test_merge_overwrites_keys
    result = LangraphRuby::State::Reducers::MERGE.call({ a: 1 }, { a: 2 })
    assert_equal({ a: 2 }, result)
  end
end
