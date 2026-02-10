# frozen_string_literal: true

require "test_helper"

class AnthropicAdapterTest < Minitest::Test
  # Mock Anthropic client for testing without API calls
  class MockAnthropicMessages
    def initialize(responses)
      @responses = responses
      @call_index = 0
    end

    def create(**params)
      response = @responses[@call_index]
      @call_index += 1
      response
    end
  end

  class MockAnthropicClient
    attr_reader :messages

    def initialize(responses)
      @messages = MockAnthropicMessages.new(responses)
    end
  end

  # Mock response objects
  ContentBlock = Struct.new(:type, :text, :id, :name, :input, keyword_init: true)
  Usage = Struct.new(:input_tokens, :output_tokens, keyword_init: true)
  Response = Struct.new(:content, :model, :stop_reason, :usage, keyword_init: true)

  def test_simple_text_response
    response = Response.new(
      content: [ContentBlock.new(type: "text", text: "Hello!")],
      model: "claude-sonnet-4-20250514",
      stop_reason: "end_turn",
      usage: Usage.new(input_tokens: 10, output_tokens: 5)
    )
    client = MockAnthropicClient.new([response])
    adapter = LangraphRuby::Adapters::AnthropicAdapter.new(client: client)

    result = adapter.chat(
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hi")]
    )

    assert_instance_of LangraphRuby::Messages::AIMessage, result
    assert_equal "Hello!", result.content
    refute result.has_tool_calls?
    assert_equal "claude-sonnet-4-20250514", result.metadata[:model]
  end

  def test_tool_call_response
    response = Response.new(
      content: [
        ContentBlock.new(type: "text", text: "Let me search that."),
        ContentBlock.new(type: "tool_use", id: "tc_123", name: "search", input: { "query" => "ruby" })
      ],
      model: "claude-sonnet-4-20250514",
      stop_reason: "tool_use",
      usage: Usage.new(input_tokens: 20, output_tokens: 15)
    )
    client = MockAnthropicClient.new([response])
    adapter = LangraphRuby::Adapters::AnthropicAdapter.new(client: client)

    result = adapter.chat(
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Search for ruby")]
    )

    assert result.has_tool_calls?
    assert_equal 1, result.tool_calls.length
    assert_equal "search", result.tool_calls[0].name
    assert_equal "tc_123", result.tool_calls[0].id
    assert_equal({ "query" => "ruby" }, result.tool_calls[0].args)
  end

  def test_multiple_tool_calls
    response = Response.new(
      content: [
        ContentBlock.new(type: "tool_use", id: "tc_1", name: "search", input: { "q" => "a" }),
        ContentBlock.new(type: "tool_use", id: "tc_2", name: "calc", input: { "expr" => "1+1" })
      ],
      model: "claude-sonnet-4-20250514",
      stop_reason: "tool_use",
      usage: Usage.new(input_tokens: 10, output_tokens: 10)
    )
    client = MockAnthropicClient.new([response])
    adapter = LangraphRuby::Adapters::AnthropicAdapter.new(client: client)

    result = adapter.chat(
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Do both")]
    )

    assert_equal 2, result.tool_calls.length
    assert_equal "search", result.tool_calls[0].name
    assert_equal "calc", result.tool_calls[1].name
  end

  def test_system_message_extracted
    response = Response.new(
      content: [ContentBlock.new(type: "text", text: "I'm helpful!")],
      model: "claude-sonnet-4-20250514",
      stop_reason: "end_turn",
      usage: Usage.new(input_tokens: 15, output_tokens: 8)
    )
    # We verify the adapter doesn't crash with system messages
    client = MockAnthropicClient.new([response])
    adapter = LangraphRuby::Adapters::AnthropicAdapter.new(client: client)

    result = adapter.chat(
      messages: [
        LangraphRuby::Messages::SystemMessage.new(content: "You are helpful."),
        LangraphRuby::Messages::HumanMessage.new(content: "Hi")
      ]
    )

    assert_equal "I'm helpful!", result.content
  end
end
