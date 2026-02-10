# frozen_string_literal: true

require "test_helper"

class ToolNodeTest < Minitest::Test
  def setup
    @search_tool = LangraphRuby::Tools::Tool.new(
      name: "search",
      description: "Search the web"
    ) { |query:| "Results for: #{query}" }

    @calc_tool = LangraphRuby::Tools::Tool.new(
      name: "calculator",
      description: "Do math"
    ) { |expression:| eval(expression).to_s }

    @tool_node = LangraphRuby::Tools::ToolNode.new(tools: [@search_tool, @calc_tool])
  end

  def test_executes_single_tool_call
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "ruby" })
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    state = { messages: [ai_msg] }

    result = @tool_node.call(state)
    assert_equal 1, result[:messages].length
    assert_instance_of LangraphRuby::Messages::ToolMessage, result[:messages][0]
    assert_equal "Results for: ruby", result[:messages][0].content
    assert_equal tc.id, result[:messages][0].tool_call_id
  end

  def test_executes_multiple_tool_calls
    tc1 = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "ruby" })
    tc2 = LangraphRuby::Messages::ToolCall.new(name: "calculator", args: { expression: "2+3" })
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc1, tc2])
    state = { messages: [ai_msg] }

    result = @tool_node.call(state)
    assert_equal 2, result[:messages].length
    assert_equal "Results for: ruby", result[:messages][0].content
    assert_equal "5", result[:messages][1].content
  end

  def test_no_tool_calls_returns_empty
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "No tools needed")
    state = { messages: [ai_msg] }

    result = @tool_node.call(state)
    assert_equal [], result[:messages]
  end

  def test_unknown_tool_raises_by_default
    tc = LangraphRuby::Messages::ToolCall.new(name: "unknown", args: {})
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    state = { messages: [ai_msg] }

    assert_raises(LangraphRuby::GraphExecutionError) do
      @tool_node.call(state)
    end
  end

  def test_handle_errors_true_returns_error_message
    node = LangraphRuby::Tools::ToolNode.new(tools: [@search_tool], handle_errors: true)
    tc = LangraphRuby::Messages::ToolCall.new(name: "unknown", args: {})
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    state = { messages: [ai_msg] }

    result = node.call(state)
    assert_equal 1, result[:messages].length
    assert_match(/not found/, result[:messages][0].content)
  end

  def test_handle_errors_with_proc
    handler = ->(error, tool_call) { "Failed to run #{tool_call.name}: #{error.message}" }
    node = LangraphRuby::Tools::ToolNode.new(tools: [@search_tool], handle_errors: handler)

    tc = LangraphRuby::Messages::ToolCall.new(name: "unknown", args: {})
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    state = { messages: [ai_msg] }

    result = node.call(state)
    assert_match(/Failed to run unknown/, result[:messages][0].content)
  end

  def test_tool_execution_error_handled
    bad_tool = LangraphRuby::Tools::Tool.new(name: "bad", description: "breaks") { raise "boom" }
    node = LangraphRuby::Tools::ToolNode.new(tools: [bad_tool], handle_errors: true)

    tc = LangraphRuby::Messages::ToolCall.new(name: "bad", args: {})
    ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    state = { messages: [ai_msg] }

    result = node.call(state)
    assert_match(/boom/, result[:messages][0].content)
  end

  def test_available_tool_names
    assert_equal ["search", "calculator"], @tool_node.available_tool_names
  end

  def test_finds_last_ai_message
    human = LangraphRuby::Messages::HumanMessage.new(content: "hi")
    ai_old = LangraphRuby::Messages::AIMessage.new(content: "old response")
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "test" })
    ai_new = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
    state = { messages: [human, ai_old, ai_new] }

    result = @tool_node.call(state)
    assert_equal 1, result[:messages].length
    assert_equal "Results for: test", result[:messages][0].content
  end
end
