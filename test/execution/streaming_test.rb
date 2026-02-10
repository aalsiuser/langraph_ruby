# frozen_string_literal: true

require "test_helper"

class StreamingTest < Minitest::Test
  def test_stream_values_mode
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:step1, ->(state) { { value: 1 } })
    g.add_node(:step2, ->(state) { { value: 2 } })
    g.add_edge(LangraphRuby::START, :step1)
    g.add_edge(:step1, :step2)
    g.add_edge(:step2, LangraphRuby::END_)

    compiled = g.compile
    snapshots = compiled.stream({}, stream_mode: :values).to_a

    # Initial state + after step1 + after step2
    assert_equal 3, snapshots.length
    assert_instance_of LangraphRuby::State::StateSnapshot, snapshots[0]
    assert_equal 0, snapshots[0].step
    assert_equal 1, snapshots[1][:value]
    assert_equal 2, snapshots[2][:value]
  end

  def test_stream_updates_mode
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:step1, ->(state) { { value: 1 } })
    g.add_node(:step2, ->(state) { { value: 2 } })
    g.add_edge(LangraphRuby::START, :step1)
    g.add_edge(:step1, :step2)
    g.add_edge(:step2, LangraphRuby::END_)

    compiled = g.compile
    updates = compiled.stream({}, stream_mode: :updates).to_a

    assert_equal 2, updates.length
    assert_equal :step1, updates[0][:node]
    assert_equal({ value: 1 }, updates[0][:update])
    assert_equal :step2, updates[1][:node]
    assert_equal({ value: 2 }, updates[1][:update])
  end

  def test_stream_with_conditional_cycle
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :count, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:increment, ->(state) { { count: 1 } })
    g.add_edge(LangraphRuby::START, :increment)
    g.add_conditional_edges(:increment, ->(s) { s[:count] >= 3 ? LangraphRuby::END_ : :increment })

    compiled = g.compile
    snapshots = compiled.stream({}, stream_mode: :values).to_a

    # Initial + 3 iterations
    assert_equal 4, snapshots.length
    assert_equal 0, snapshots[0][:count]
    assert_equal 1, snapshots[1][:count]
    assert_equal 2, snapshots[2][:count]
    assert_equal 3, snapshots[3][:count]
  end

  def test_stream_returns_enumerator
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { { v: 1 } })
    g.add_edge(LangraphRuby::START, :a)
    g.add_edge(:a, LangraphRuby::END_)

    compiled = g.compile
    stream = compiled.stream({})
    assert_instance_of Enumerator, stream
  end

  def test_stream_lazy_composable
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { { v: 1 } })
    g.add_node(:b, ->(s) { { v: 2 } })
    g.add_node(:c, ->(s) { { v: 3 } })
    g.add_edge(LangraphRuby::START, :a)
    g.add_edge(:a, :b)
    g.add_edge(:b, :c)
    g.add_edge(:c, LangraphRuby::END_)

    compiled = g.compile
    values = compiled.stream({}, stream_mode: :updates)
      .lazy
      .map { |u| u[:update][:v] }
      .select { |v| v > 1 }
      .to_a

    assert_equal [2, 3], values
  end
end
