# frozen_string_literal: true

require "test_helper"

class MessageTypesTest < Minitest::Test
  def test_human_message
    msg = LangraphRuby::Messages::HumanMessage.new(content: "What is Ruby?")
    assert_equal "human", msg.type
    assert_equal "What is Ruby?", msg.content
  end

  def test_ai_message_without_tool_calls
    msg = LangraphRuby::Messages::AIMessage.new(content: "Ruby is a language.")
    assert_equal "ai", msg.type
    refute msg.has_tool_calls?
    assert_equal [], msg.tool_calls
  end

  def test_ai_message_with_tool_calls
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "ruby" })
    msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    assert msg.has_tool_calls?
    assert_equal 1, msg.tool_calls.length
    assert_equal "search", msg.tool_calls.first.name
  end

  def test_tool_message
    msg = LangraphRuby::Messages::ToolMessage.new(
      content: "result data",
      tool_call_id: "tc-1",
      tool_name: "search"
    )
    assert_equal "tool", msg.type
    assert_equal "tc-1", msg.tool_call_id
    assert_equal "search", msg.tool_name
  end

  def test_system_message
    msg = LangraphRuby::Messages::SystemMessage.new(content: "You are a helpful assistant.")
    assert_equal "system", msg.type
  end

  def test_tool_call
    tc = LangraphRuby::Messages::ToolCall.new(name: "calc", args: { expr: "2+2" }, id: "tc-42")
    assert_equal "tc-42", tc.id
    assert_equal "calc", tc.name
    assert_equal({ expr: "2+2" }, tc.args)
    assert_equal({ id: "tc-42", name: "calc", args: { expr: "2+2" } }, tc.to_h)
  end

  def test_ai_message_to_h_includes_tool_calls
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: {}, id: "tc-1")
    msg = LangraphRuby::Messages::AIMessage.new(content: "let me search", tool_calls: [tc], id: "ai-1")
    h = msg.to_h
    assert_equal [{ id: "tc-1", name: "search", args: {} }], h[:tool_calls]
  end
end
