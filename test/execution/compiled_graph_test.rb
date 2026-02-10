# frozen_string_literal: true

require "test_helper"

class CompiledGraphTest < Minitest::Test
  def test_simple_linear_graph
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:add_greeting, ->(state) { { output: "Hello, #{state[:name]}!" } })
    g.add_edge(LangraphRuby::START, :add_greeting)
    g.add_edge(:add_greeting, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({ name: "World" })
    assert_equal "Hello, World!", result[:output]
  end

  def test_multi_step_linear_graph
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:step1, ->(state) { { value: (state[:value] || 0) + 1 } })
    g.add_node(:step2, ->(state) { { value: state[:value] * 10 } })
    g.add_edge(LangraphRuby::START, :step1)
    g.add_edge(:step1, :step2)
    g.add_edge(:step2, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal 10, result[:value]
  end

  def test_conditional_edges
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:classify, ->(state) { { category: state[:input].length > 5 ? :long : :short } })
    g.add_node(:handle_long, ->(state) { { result: "long input" } })
    g.add_node(:handle_short, ->(state) { { result: "short input" } })

    g.add_edge(LangraphRuby::START, :classify)
    g.add_conditional_edges(:classify, ->(s) { s[:category] }, { long: :handle_long, short: :handle_short })
    g.add_edge(:handle_long, LangraphRuby::END_)
    g.add_edge(:handle_short, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({ input: "hello world" })
    assert_equal "long input", result[:result]

    result = compiled.invoke({ input: "hi" })
    assert_equal "short input", result[:result]
  end

  def test_conditional_edges_without_mapping
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:router, ->(state) { state })
    g.add_node(:a, ->(state) { { result: "went to a" } })
    g.add_node(:b, ->(state) { { result: "went to b" } })

    g.add_edge(LangraphRuby::START, :router)
    g.add_conditional_edges(:router, ->(s) { s[:target] })
    g.add_edge(:a, LangraphRuby::END_)
    g.add_edge(:b, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({ target: :a })
    assert_equal "went to a", result[:result]
  end

  def test_cycle_with_max_steps
    counter = 0
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:loop, ->(state) { { count: (state[:count] || 0) + 1 } })

    g.add_edge(LangraphRuby::START, :loop)
    g.add_conditional_edges(:loop, ->(s) { s[:count] >= 3 ? LangraphRuby::END_ : :loop })

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal 3, result[:count]
  end

  def test_max_steps_exceeded_raises
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:infinite, ->(state) { { count: (state[:count] || 0) + 1 } })
    g.add_edge(LangraphRuby::START, :infinite)
    g.add_edge(:infinite, :infinite)

    compiled = g.compile
    assert_raises(LangraphRuby::MaxStepsReachedError) do
      compiled.invoke({}, config: { max_steps: 5 })
    end
  end

  def test_graph_with_schema
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
      field :count, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:process, ->(state) {
      msg = LangraphRuby::Messages::AIMessage.new(content: "processed")
      { messages: [msg], count: 1 }
    })
    g.add_edge(LangraphRuby::START, :process)
    g.add_edge(:process, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal 1, result[:messages].length
    assert_equal 1, result[:count]
  end

  def test_schema_reducer_accumulates
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :total, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:add5, ->(state) { { total: 5 } })
    g.add_node(:add3, ->(state) { { total: 3 } })
    g.add_edge(LangraphRuby::START, :add5)
    g.add_edge(:add5, :add3)
    g.add_edge(:add3, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal 8, result[:total]
  end

  def test_node_execution_error_wraps
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:bad, ->(state) { raise "something broke" })
    g.add_edge(LangraphRuby::START, :bad)
    g.add_edge(:bad, LangraphRuby::END_)

    compiled = g.compile
    assert_raises(LangraphRuby::GraphExecutionError) do
      compiled.invoke({})
    end
  end
end
