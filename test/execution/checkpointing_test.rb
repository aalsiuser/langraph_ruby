# frozen_string_literal: true

require "test_helper"

class CheckpointingTest < Minitest::Test
  def setup
    @checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new
  end

  def test_checkpoints_saved_during_execution
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:step1, ->(s) { { value: 1 } })
    g.add_node(:step2, ->(s) { { value: 2 } })
    g.add_edge(LangraphRuby::START, :step1)
    g.add_edge(:step1, :step2)
    g.add_edge(:step2, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)
    compiled.invoke({}, config: { thread_id: "t1" })

    history = @checkpointer.list("t1")
    assert history.length >= 2
  end

  def test_get_state
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:inc, ->(s) { { value: (s[:value] || 0) + 1 } })
    g.add_edge(LangraphRuby::START, :inc)
    g.add_edge(:inc, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)
    compiled.invoke({ value: 10 }, config: { thread_id: "t1" })

    state = compiled.get_state({ thread_id: "t1" })
    assert_equal 11, state[:value]
  end

  def test_get_state_history
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :count, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:inc, ->(s) { { count: 1 } })
    g.add_edge(LangraphRuby::START, :inc)
    g.add_conditional_edges(:inc, ->(s) { s[:count] >= 3 ? LangraphRuby::END_ : :inc })

    compiled = g.compile(checkpointer: @checkpointer)
    compiled.invoke({}, config: { thread_id: "t1" })

    history = compiled.get_state_history({ thread_id: "t1" })
    assert history.length >= 3
    # Latest first
    assert history[0].step >= history[1].step
  end

  def test_update_state
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:proc, ->(s) { { result: s[:value] * 2 } })
    g.add_edge(LangraphRuby::START, :proc)
    g.add_edge(:proc, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)
    compiled.invoke({ value: 5 }, config: { thread_id: "t1" })

    new_state = compiled.update_state({ result: 999 }, { thread_id: "t1" })
    assert_equal 999, new_state[:result]

    latest = compiled.get_state({ thread_id: "t1" })
    assert_equal 999, latest[:result]
  end

  def test_thread_isolation
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:proc, ->(s) { { value: s[:input] } })
    g.add_edge(LangraphRuby::START, :proc)
    g.add_edge(:proc, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)
    compiled.invoke({ input: "thread1" }, config: { thread_id: "t1" })
    compiled.invoke({ input: "thread2" }, config: { thread_id: "t2" })

    s1 = compiled.get_state({ thread_id: "t1" })
    s2 = compiled.get_state({ thread_id: "t2" })
    assert_equal "thread1", s1[:value]
    assert_equal "thread2", s2[:value]
  end

  def test_no_checkpointer_still_works
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:proc, ->(s) { { v: 1 } })
    g.add_edge(LangraphRuby::START, :proc)
    g.add_edge(:proc, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal 1, result[:v]
  end

  def test_streaming_with_checkpointer
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { { v: 1 } })
    g.add_node(:b, ->(s) { { v: 2 } })
    g.add_edge(LangraphRuby::START, :a)
    g.add_edge(:a, :b)
    g.add_edge(:b, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)
    compiled.stream({}, config: { thread_id: "t1" }, stream_mode: :values).to_a

    state = compiled.get_state({ thread_id: "t1" })
    assert_equal 2, state[:v]
  end
end
