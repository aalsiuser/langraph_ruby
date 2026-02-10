# frozen_string_literal: true

require "test_helper"

class ReactAgentTest < Minitest::Test
  # A mock adapter that returns pre-programmed responses
  class MockAdapter < LangraphRuby::Adapters::BaseAdapter
    def initialize(responses)
      @responses = responses
      @call_index = 0
    end

    def chat(messages:, tools: [], **config)
      response = @responses[@call_index]
      @call_index += 1
      response
    end

    def call_count
      @call_index
    end
  end

  def setup
    @search_tool = LangraphRuby::Tools::Tool.new(
      name: "search",
      description: "Search the web",
      parameters: { query: { type: "string", description: "Query", required: true } }
    ) { |query:| "Results for: #{query}" }

    @calc_tool = LangraphRuby::Tools::Tool.new(
      name: "calculator",
      description: "Calculate math",
      parameters: { expression: { type: "string", description: "Math expression", required: true } }
    ) { |expression:| "42" }
  end

  def test_direct_response_no_tools
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "Hello! How can I help?")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool]
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hi")]
    })

    assert_equal 2, result[:messages].length
    assert_equal "Hello! How can I help?", result[:messages].last.content
    assert_equal 1, adapter.call_count
  end

  def test_single_tool_call_loop
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "ruby lang" })
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc]),
      LangraphRuby::Messages::AIMessage.new(content: "Ruby is a great programming language!")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool]
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Tell me about Ruby")]
    })

    # human → ai(tool_call) → tool_result → ai(response)
    assert_equal 4, result[:messages].length
    assert_instance_of LangraphRuby::Messages::HumanMessage, result[:messages][0]
    assert_instance_of LangraphRuby::Messages::AIMessage, result[:messages][1]
    assert result[:messages][1].has_tool_calls?
    assert_instance_of LangraphRuby::Messages::ToolMessage, result[:messages][2]
    assert_equal "Results for: ruby lang", result[:messages][2].content
    assert_instance_of LangraphRuby::Messages::AIMessage, result[:messages][3]
    assert_equal "Ruby is a great programming language!", result[:messages][3].content
    assert_equal 2, adapter.call_count
  end

  def test_multi_tool_call_loop
    tc1 = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "population" })
    tc2 = LangraphRuby::Messages::ToolCall.new(name: "calculator", args: { expression: "7+3" })
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc1, tc2]),
      LangraphRuby::Messages::AIMessage.new(content: "The answer is 42.")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool, @calc_tool]
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Complex query")]
    })

    # human → ai(2 tool_calls) → tool_result_1 → tool_result_2 → ai(response)
    assert_equal 5, result[:messages].length
    assert_equal 2, adapter.call_count
  end

  def test_multiple_tool_rounds
    tc1 = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "first" })
    tc2 = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "second" })
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc1]),
      LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc2]),
      LangraphRuby::Messages::AIMessage.new(content: "Done after two searches.")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool]
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Research this")]
    })

    # human → ai(tc1) → tool1 → ai(tc2) → tool2 → ai(final)
    assert_equal 6, result[:messages].length
    assert_equal 3, adapter.call_count
    assert_equal "Done after two searches.", result[:messages].last.content
  end

  def test_with_system_prompt
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "I am a pirate! Arrr!")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool],
      system_prompt: "You are a pirate. Always speak like a pirate."
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hi")]
    })

    assert_equal 2, result[:messages].length
    assert_equal "I am a pirate! Arrr!", result[:messages].last.content
  end

  def test_streaming_react_agent
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "test" })
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc]),
      LangraphRuby::Messages::AIMessage.new(content: "Final answer")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool]
    )

    updates = agent.stream(
      { messages: [LangraphRuby::Messages::HumanMessage.new(content: "Q")] },
      stream_mode: :updates
    ).to_a

    node_names = updates.map { |u| u[:node] }
    assert_equal [:agent, :tools, :agent], node_names
  end

  def test_tool_error_handled_gracefully
    bad_tool = LangraphRuby::Tools::Tool.new(
      name: "broken",
      description: "Always fails"
    ) { raise "kaboom" }

    tc = LangraphRuby::Messages::ToolCall.new(name: "broken", args: {})
    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc]),
      LangraphRuby::Messages::AIMessage.new(content: "Tool failed, but I handled it.")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [bad_tool]
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Try the broken tool")]
    })

    # Tool error should be captured as ToolMessage
    tool_msg = result[:messages].find { |m| m.is_a?(LangraphRuby::Messages::ToolMessage) }
    assert_match(/kaboom/, tool_msg.content)
    assert_equal "Tool failed, but I handled it.", result[:messages].last.content
  end

  def test_custom_state_schema
    custom_schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
      field :metadata, type: Hash, default: -> { {} }, reducer: :merge
    end

    adapter = MockAdapter.new([
      LangraphRuby::Messages::AIMessage.new(content: "Done")
    ])

    agent = LangraphRuby::Agents::ReactAgent.create(
      adapter: adapter,
      tools: [@search_tool],
      state_schema: custom_schema
    )

    result = agent.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hi")],
      metadata: { source: "test" }
    })

    assert_equal({ source: "test" }, result[:metadata])
    assert_equal 2, result[:messages].length
  end
end
