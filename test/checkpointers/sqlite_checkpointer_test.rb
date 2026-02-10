# frozen_string_literal: true

require "test_helper"

class SqliteCheckpointerTest < Minitest::Test
  def setup
    @checkpointer = LangraphRuby::Checkpointers::SqliteCheckpointer.new(db_path: ":memory:")
  end

  def teardown
    @checkpointer.close
  end

  def test_save_and_load_simple_state
    cp = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { count: 5, name: "test" }, next_nodes: [:agent], step: 1
    )
    @checkpointer.save(cp)

    loaded = @checkpointer.load("t1")
    assert_equal cp.id, loaded.id
    assert_equal 5, loaded.state[:count]
    assert_equal "test", loaded.state[:name]
    assert_equal [:agent], loaded.next_nodes
    assert_equal 1, loaded.step
  end

  def test_save_and_load_with_messages
    msg1 = LangraphRuby::Messages::HumanMessage.new(content: "hello", id: "h1")
    msg2 = LangraphRuby::Messages::AIMessage.new(content: "hi there", id: "a1")
    tc = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "test" }, id: "tc1")
    msg3 = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tc], id: "a2")
    msg4 = LangraphRuby::Messages::ToolMessage.new(
      content: "result", tool_call_id: "tc1", tool_name: "search", id: "tm1"
    )

    cp = LangraphRuby::Checkpointers::Checkpoint.new(
      thread_id: "t1", state: { messages: [msg1, msg2, msg3, msg4] }, step: 3
    )
    @checkpointer.save(cp)

    loaded = @checkpointer.load("t1")
    messages = loaded.state[:messages]
    assert_equal 4, messages.length

    assert_instance_of LangraphRuby::Messages::HumanMessage, messages[0]
    assert_equal "hello", messages[0].content
    assert_equal "h1", messages[0].id

    assert_instance_of LangraphRuby::Messages::AIMessage, messages[1]
    assert_equal "hi there", messages[1].content

    assert_instance_of LangraphRuby::Messages::AIMessage, messages[2]
    assert messages[2].has_tool_calls?
    assert_equal "search", messages[2].tool_calls[0].name
    assert_equal({ "query" => "test" }, messages[2].tool_calls[0].args)

    assert_instance_of LangraphRuby::Messages::ToolMessage, messages[3]
    assert_equal "tc1", messages[3].tool_call_id
  end

  def test_load_returns_latest
    @checkpointer.save(
      LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: { v: 1 }, step: 1)
    )
    @checkpointer.save(
      LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: { v: 2 }, step: 2)
    )

    loaded = @checkpointer.load("t1")
    assert_equal 2, loaded.state[:v]
  end

  def test_load_by_id
    cp1 = LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: { v: 1 }, step: 1)
    cp2 = LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: { v: 2 }, step: 2)
    @checkpointer.save(cp1)
    @checkpointer.save(cp2)

    loaded = @checkpointer.load_by_id("t1", cp1.id)
    assert_equal 1, loaded.state[:v]
  end

  def test_list_newest_first
    3.times do |i|
      @checkpointer.save(
        LangraphRuby::Checkpointers::Checkpoint.new(thread_id: "t1", state: { i: i }, step: i)
      )
    end

    history = @checkpointer.list("t1")
    assert_equal 3, history.length
    assert_equal 2, history[0].step
    assert_equal 0, history[2].step
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
      interrupted_node: :review, interrupt_value: "please approve"
    )
    @checkpointer.save(cp)

    loaded = @checkpointer.load("t1")
    assert loaded.interrupted?
    assert_equal :review, loaded.interrupted_node
    assert_equal "please approve", loaded.interrupt_value
  end
end
