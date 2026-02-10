# frozen_string_literal: true

require "test_helper"

class AgentWorkflowTest < Minitest::Test
  # Simulates a ReAct-style agent workflow:
  # Agent thinks → decides to use tool or respond → tool runs → agent sees result → responds
  def test_react_style_agent
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
      field :tool_pending, type: Object, default: false
    end

    # Simulated "agent" node — on first call makes a tool call, on second call responds
    call_count = 0
    agent_node = ->(state) {
      call_count += 1
      if call_count == 1
        tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "ruby lang" })
        ai_msg = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])
        { messages: [ai_msg], tool_pending: true }
      else
        ai_msg = LangraphRuby::Messages::AIMessage.new(content: "Ruby is a great language!")
        { messages: [ai_msg], tool_pending: false }
      end
    }

    # Simulated "tools" node
    tools_node = ->(state) {
      last_ai = state[:messages].select { |m| m.is_a?(LangraphRuby::Messages::AIMessage) }.last
      tool_call = last_ai.tool_calls.first
      tool_msg = LangraphRuby::Messages::ToolMessage.new(
        content: "Ruby is an interpreted language created by Matz",
        tool_call_id: tool_call.id,
        tool_name: tool_call.name
      )
      { messages: [tool_msg], tool_pending: false }
    }

    # Should we call tools or end?
    should_continue = ->(state) {
      state[:tool_pending] ? :tools : LangraphRuby::END_
    }

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:agent, agent_node)
    g.add_node(:tools, tools_node)
    g.add_edge(LangraphRuby::START, :agent)
    g.add_conditional_edges(:agent, should_continue)
    g.add_edge(:tools, :agent)

    compiled = g.compile
    result = compiled.invoke({
      messages: [LangraphRuby::Messages::HumanMessage.new(content: "Tell me about Ruby")]
    })

    # Should have: human → ai(tool_call) → tool_result → ai(response)
    assert_equal 4, result[:messages].length
    assert_instance_of LangraphRuby::Messages::HumanMessage, result[:messages][0]
    assert_instance_of LangraphRuby::Messages::AIMessage, result[:messages][1]
    assert result[:messages][1].has_tool_calls?
    assert_instance_of LangraphRuby::Messages::ToolMessage, result[:messages][2]
    assert_instance_of LangraphRuby::Messages::AIMessage, result[:messages][3]
    assert_equal "Ruby is a great language!", result[:messages][3].content
    refute result[:tool_pending]
  end

  def test_multi_branch_router
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :query, type: String
      field :category, type: String
      field :result, type: String
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:classify, ->(state) {
      category = case state[:query]
                 when /weather/ then :weather
                 when /math|calc/ then :math
                 else :general
                 end
      { category: category }
    })
    g.add_node(:weather, ->(state) { { result: "It's sunny!" } })
    g.add_node(:math, ->(state) { { result: "42" } })
    g.add_node(:general, ->(state) { { result: "I can help with that." } })

    g.add_edge(LangraphRuby::START, :classify)
    g.add_conditional_edges(:classify, ->(s) { s[:category] },
      { weather: :weather, math: :math, general: :general })
    g.add_edge(:weather, LangraphRuby::END_)
    g.add_edge(:math, LangraphRuby::END_)
    g.add_edge(:general, LangraphRuby::END_)

    compiled = g.compile

    assert_equal "It's sunny!", compiled.invoke({ query: "what's the weather?" })[:result]
    assert_equal "42", compiled.invoke({ query: "do some math" })[:result]
    assert_equal "I can help with that.", compiled.invoke({ query: "hello" })[:result]
  end

  def test_iterative_refinement_loop
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :draft, type: String, default: ""
      field :score, type: Integer, default: 0
      field :iterations, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:write, ->(state) {
      iteration = state[:iterations] + 1
      { draft: "Draft v#{iteration}", score: iteration * 30, iterations: 1 }
    })
    g.add_node(:evaluate, ->(state) { state.slice }) # passthrough, score already set
    g.add_edge(LangraphRuby::START, :write)
    g.add_edge(:write, :evaluate)
    g.add_conditional_edges(:evaluate, ->(s) {
      s[:score] >= 90 ? LangraphRuby::END_ : :write
    })

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal "Draft v3", result[:draft]
    assert_equal 90, result[:score]
    assert_equal 3, result[:iterations]
  end

  def test_streaming_react_agent
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
      field :done, type: Object, default: false
    end

    step = 0
    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:agent, ->(state) {
      step += 1
      if step <= 2
        tc = LangraphRuby::Messages::ToolCall.new(name: "lookup", args: {})
        { messages: [LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc])], done: false }
      else
        { messages: [LangraphRuby::Messages::AIMessage.new(content: "Final answer")], done: true }
      end
    })
    g.add_node(:tools, ->(state) {
      ai = state[:messages].select { |m| m.is_a?(LangraphRuby::Messages::AIMessage) }.last
      tc = ai.tool_calls.first
      { messages: [LangraphRuby::Messages::ToolMessage.new(content: "data", tool_call_id: tc.id, tool_name: tc.name)] }
    })
    g.add_edge(LangraphRuby::START, :agent)
    g.add_conditional_edges(:agent, ->(s) { s[:done] ? LangraphRuby::END_ : :tools })
    g.add_edge(:tools, :agent)

    compiled = g.compile
    updates = compiled.stream({}, stream_mode: :updates).to_a
    node_names = updates.map { |u| u[:node] }

    # agent → tools → agent → tools → agent (final)
    assert_equal [:agent, :tools, :agent, :tools, :agent], node_names
  end

  def test_dsl_block_style
    compiled = LangraphRuby::Graph::StateGraph.new do
      node :greet, ->(s) { { greeting: "Hello, #{s[:name]}!" } }
      edge LangraphRuby::START => :greet
      edge :greet => LangraphRuby::END_
    end.compile

    result = compiled.invoke({ name: "Ruby" })
    assert_equal "Hello, Ruby!", result[:greeting]
  end
end
