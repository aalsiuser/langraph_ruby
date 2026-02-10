# frozen_string_literal: true

require "test_helper"

class BaseMessageTest < Minitest::Test
  def test_creates_message_with_auto_id
    msg = LangraphRuby::Messages::BaseMessage.new(content: "hello", type: "test")
    assert msg.id
    assert_equal "hello", msg.content
    assert_equal "test", msg.type
  end

  def test_creates_message_with_custom_id
    msg = LangraphRuby::Messages::BaseMessage.new(content: "hello", type: "test", id: "custom-id")
    assert_equal "custom-id", msg.id
  end

  def test_equality_by_id
    msg1 = LangraphRuby::Messages::BaseMessage.new(content: "a", type: "test", id: "same")
    msg2 = LangraphRuby::Messages::BaseMessage.new(content: "b", type: "test", id: "same")
    assert_equal msg1, msg2
  end

  def test_to_h
    msg = LangraphRuby::Messages::BaseMessage.new(content: "hi", type: "test", id: "1")
    expected = { id: "1", type: "test", content: "hi", metadata: {} }
    assert_equal expected, msg.to_h
  end

  def test_metadata
    msg = LangraphRuby::Messages::BaseMessage.new(content: "hi", type: "test", metadata: { source: "api" })
    assert_equal({ source: "api" }, msg.metadata)
  end
end
