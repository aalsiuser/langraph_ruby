# frozen_string_literal: true

require "test_helper"

class MemoryCheckpointerTest < Minitest::Test
  def setup
    @checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new
  end

  def test_save_and_load
    cp = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { count: 1 }, next_nodes: [:a], step: 1
    )
    @checkpointer.save(cp)

    loaded = @checkpointer.load("t1")
    assert_equal cp.id, loaded.id
    assert_equal({ count: 1 }, loaded.state)
    assert_equal [:a], loaded.next_nodes
  end

  def test_load_returns_latest
    cp1 = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { step: 1 }, step: 1
    )
    cp2 = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { step: 2 }, step: 2
    )
    @checkpointer.save(cp1)
    @checkpointer.save(cp2)

    loaded = @checkpointer.load("t1")
    assert_equal cp2.id, loaded.id
    assert_equal 2, loaded.state[:step]
  end

  def test_load_nonexistent_returns_nil
    assert_nil @checkpointer.load("nonexistent")
  end

  def test_load_by_id
    cp1 = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { v: 1 }, step: 1
    )
    cp2 = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { v: 2 }, step: 2
    )
    @checkpointer.save(cp1)
    @checkpointer.save(cp2)

    loaded = @checkpointer.load_by_id("t1", cp1.id)
    assert_equal cp1.id, loaded.id
    assert_equal 1, loaded.state[:v]
  end

  def test_list_returns_newest_first
    3.times do |i|
      cp = LangraphRuby::Checkpointers::Checkpoint.new(
        thread_id: "t1", state: { i: i }, step: i
      )
      @checkpointer.save(cp)
    end

    history = @checkpointer.list("t1")
    assert_equal 3, history.length
    assert_equal 2, history[0].state[:i]
    assert_equal 0, history[2].state[:i]
  end

  def test_thread_isolation
    @checkpointer.save(
      LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: { v: 1 }, step: 1)
    )
    @checkpointer.save(
      LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t2", state: { v: 2 }, step: 1)
    )

    assert_equal 1, @checkpointer.load("t1").state[:v]
    assert_equal 2, @checkpointer.load("t2").state[:v]
    assert_equal 1, @checkpointer.list("t1").length
    assert_equal 1, @checkpointer.list("t2").length
  end

  def test_delete
    @checkpointer.save(
      LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: {}, step: 1)
    )
    @checkpointer.delete("t1")
    assert_nil @checkpointer.load("t1")
  end

  def test_interrupted_checkpoint
    cp = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { v: 1 }, step: 1,
      interrupted_node: :review, interrupt_value: { draft: "hello" }
    )
    @checkpointer.save(cp)

    loaded = @checkpointer.load("t1")
    assert loaded.interrupted?
    assert_equal :review, loaded.interrupted_node
    assert_equal({ draft: "hello" }, loaded.interrupt_value)
  end
end
