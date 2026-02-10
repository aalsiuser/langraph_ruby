# frozen_string_literal: true

require "test_helper"

class SubgraphTest < Minitest::Test
  def test_subgraph_as_node
    # Child graph: doubles a value
    child = LangraphRuby::Graph::StateGraph.new
    child.add_node(:double, ->(s) { { value: s[:value] * 2 } })
    child.add_edge(LangraphRuby::START, :double)
    child.add_edge(:double, LangraphRuby::END_)
    compiled_child = child.compile

    # Parent graph: uses child as a node
    parent = LangraphRuby::Graph::StateGraph.new
    parent.add_node(:init, ->(s) { { value: 5 } })
    parent.add_node(:process, LangraphRuby::Graph::Subgraph.new(compiled_child))
    parent.add_edge(LangraphRuby::START, :init)
    parent.add_edge(:init, :process)
    parent.add_edge(:process, LangraphRuby::END_)

    compiled_parent = parent.compile
    result = compiled_parent.invoke({})
    assert_equal 10, result[:value]
  end

  def test_subgraph_with_input_output_mapping
    # Child graph: greets by name
    child = LangraphRuby::Graph::StateGraph.new
    child.add_node(:greet, ->(s) { { greeting: "Hello, #{s[:name]}!" } })
    child.add_edge(LangraphRuby::START, :greet)
    child.add_edge(:greet, LangraphRuby::END_)
    compiled_child = child.compile

    # Parent uses different key names
    subgraph = LangraphRuby::Graph::Subgraph.new(
      compiled_child,
      input_map: { user_name: :name },
      output_map: { greeting: :welcome_message }
    )

    parent = LangraphRuby::Graph::StateGraph.new
    parent.add_node(:greet, subgraph)
    parent.add_edge(LangraphRuby::START, :greet)
    parent.add_edge(:greet, LangraphRuby::END_)

    compiled_parent = parent.compile
    result = compiled_parent.invoke({ user_name: "Ruby" })
    assert_equal "Hello, Ruby!", result[:welcome_message]
    assert_nil result[:greeting] # child key not leaked to parent
  end

  def test_nested_subgraphs
    # Innermost: adds 1
    inner = LangraphRuby::Graph::StateGraph.new
    inner.add_node(:add1, ->(s) { { value: s[:value] + 1 } })
    inner.add_edge(LangraphRuby::START, :add1)
    inner.add_edge(:add1, LangraphRuby::END_)

    # Middle: wraps inner, then multiplies by 2
    middle = LangraphRuby::Graph::StateGraph.new
    middle.add_node(:inner, LangraphRuby::Graph::Subgraph.new(inner.compile))
    middle.add_node(:mul2, ->(s) { { value: s[:value] * 2 } })
    middle.add_edge(LangraphRuby::START, :inner)
    middle.add_edge(:inner, :mul2)
    middle.add_edge(:mul2, LangraphRuby::END_)

    # Outer: sets initial value, runs middle
    outer = LangraphRuby::Graph::StateGraph.new
    outer.add_node(:setup, ->(s) { { value: 3 } })
    outer.add_node(:middle, LangraphRuby::Graph::Subgraph.new(middle.compile))
    outer.add_edge(LangraphRuby::START, :setup)
    outer.add_edge(:setup, :middle)
    outer.add_edge(:middle, LangraphRuby::END_)

    result = outer.compile.invoke({})
    # (3 + 1) * 2 = 8
    assert_equal 8, result[:value]
  end

  def test_subgraph_with_schema
    child_schema = Class.new(LangraphRuby::State::StateSchema) do
      field :items, type: Array, reducer: :append
    end

    child = LangraphRuby::Graph::StateGraph.new(child_schema)
    child.add_node(:add, ->(s) { { items: ["added"] } })
    child.add_edge(LangraphRuby::START, :add)
    child.add_edge(:add, LangraphRuby::END_)

    parent = LangraphRuby::Graph::StateGraph.new
    parent.add_node(:run, LangraphRuby::Graph::Subgraph.new(child.compile))
    parent.add_edge(LangraphRuby::START, :run)
    parent.add_edge(:run, LangraphRuby::END_)

    result = parent.compile.invoke({})
    assert_equal ["added"], result[:items]
  end
end
