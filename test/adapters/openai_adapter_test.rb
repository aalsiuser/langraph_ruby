# frozen_string_literal: true

require "test_helper"
require "json"

class OpenAiAdapterTest < Minitest::Test
  # Mock OpenAI client
  class MockOpenAiClient
    def initialize(responses)
      @responses = responses
      @call_index = 0
    end

    def chat(parameters:)
      response = @responses[@call_index]
      @call_index += 1
      response
    end
  end

  def test_simple_text_response
    response = {
      "choices" => [{
        "message" => { "content" => "Hello!", "role" => "assistant" },
        "finish_reason" => "stop"
      }],
      "model" => "gpt-4o",
      "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 }
    }
    client = MockOpenAiClient.new([response])
    adapter = LangraphRuby::Adapters::OpenAiAdapter.new(client: client)

    result = adapter.chat(
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hi")]
    )

    assert_instance_of LangraphRuby::Messages::AIMessage, result
    assert_equal "Hello!", result.content
    refute result.has_tool_calls?
    assert_equal "gpt-4o", result.metadata[:model]
  end

  def test_tool_call_response
    response = {
      "choices" => [{
        "message" => {
          "content" => nil,
          "role" => "assistant",
          "tool_calls" => [{
            "id" => "call_abc",
            "type" => "function",
            "function" => {
              "name" => "search",
              "arguments" => '{"query":"ruby"}'
            }
          }]
        },
        "finish_reason" => "tool_calls"
      }],
      "model" => "gpt-4o",
      "usage" => { "prompt_tokens" => 20, "completion_tokens" => 15 }
    }
    client = MockOpenAiClient.new([response])
    adapter = LangraphRuby::Adapters::OpenAiAdapter.new(client: client)

    result = adapter.chat(
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Search ruby")]
    )

    assert result.has_tool_calls?
    assert_equal 1, result.tool_calls.length
    assert_equal "search", result.tool_calls[0].name
    assert_equal "call_abc", result.tool_calls[0].id
    assert_equal({ "query" => "ruby" }, result.tool_calls[0].args)
  end

  def test_multiple_tool_calls
    response = {
      "choices" => [{
        "message" => {
          "content" => "",
          "role" => "assistant",
          "tool_calls" => [
            { "id" => "c1", "type" => "function", "function" => { "name" => "search", "arguments" => '{"q":"a"}' } },
            { "id" => "c2", "type" => "function", "function" => { "name" => "calc", "arguments" => '{"expr":"1+1"}' } }
          ]
        },
        "finish_reason" => "tool_calls"
      }],
      "model" => "gpt-4o",
      "usage" => {}
    }
    client = MockOpenAiClient.new([response])
    adapter = LangraphRuby::Adapters::OpenAiAdapter.new(client: client)

    result = adapter.chat(
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "both")]
    )

    assert_equal 2, result.tool_calls.length
    assert_equal "search", result.tool_calls[0].name
    assert_equal "calc", result.tool_calls[1].name
  end

  def test_system_message_formatting
    response = {
      "choices" => [{
        "message" => { "content" => "Helpful response", "role" => "assistant" },
        "finish_reason" => "stop"
      }],
      "model" => "gpt-4o",
      "usage" => {}
    }
    client = MockOpenAiClient.new([response])
    adapter = LangraphRuby::Adapters::OpenAiAdapter.new(client: client)

    result = adapter.chat(
      messages: [
        LangraphRuby::Messages::SystemMessage.new(content: "Be helpful"),
        LangraphRuby::Messages::HumanMessage.new(content: "Hi")
      ]
    )

    assert_equal "Helpful response", result.content
  end
end
