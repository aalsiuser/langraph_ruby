# frozen_string_literal: true

require "test_helper"

class InterruptTest < Minitest::Test
  def setup
    @checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new
  end

  def test_interrupt_before
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:draft, ->(s) { { draft: "Hello email" } })
    g.add_node(:send, ->(s) { { sent: true } })
    g.add_edge(LangraphRuby::START, :draft)
    g.add_edge(:draft, :send)
    g.add_edge(:send, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer, interrupt_before: [:send])
    result = compiled.invoke({}, config: { thread_id: "t1" })

    assert_instance_of LangraphRuby::Execution::InterruptResult, result
    assert result.interrupted?
    assert_equal :send, result.interrupted_node
    assert_equal :before, result.interrupt_kind
    assert_equal "Hello email", result[:draft]
  end

  def test_interrupt_before_resume
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:draft, ->(s) { { draft: "Hello email" } })
    g.add_node(:send, ->(s) { { sent: true, draft: s[:draft] } })
    g.add_edge(LangraphRuby::START, :draft)
    g.add_edge(:draft, :send)
    g.add_edge(:send, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer, interrupt_before: [:send])

    # First invoke — pauses before :send
    result = compiled.invoke({}, config: { thread_id: "t1" })
    assert result.interrupted?
    assert_equal :send, result.interrupted_node

    # Resume — executes :send
    final = compiled.invoke(nil, config: { thread_id: "t1", resume: true })
    assert_equal true, final[:sent]
    assert_equal "Hello email", final[:draft]
  end

  def test_interrupt_after
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:generate, ->(s) { { output: "Generated content" } })
    g.add_node(:publish, ->(s) { { published: true } })
    g.add_edge(LangraphRuby::START, :generate)
    g.add_edge(:generate, :publish)
    g.add_edge(:publish, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer, interrupt_after: [:generate])
    result = compiled.invoke({}, config: { thread_id: "t1" })

    assert result.interrupted?
    assert_equal :generate, result.interrupted_node
    assert_equal :after, result.interrupt_kind
    assert_equal "Generated content", result[:output]
  end

  def test_dynamic_interrupt
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:check, ->(s) {
      if s[:amount] && s[:amount] > 1000
        LangraphRuby.interrupt({ reason: "High value transfer", amount: s[:amount] })
      end
      { approved: true }
    })
    g.add_edge(LangraphRuby::START, :check)
    g.add_edge(:check, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)

    # Low value — no interrupt
    result = compiled.invoke({ amount: 100 }, config: { thread_id: "t1" })
    refute result.is_a?(LangraphRuby::Execution::InterruptResult)
    assert_equal true, result[:approved]

    # High value — interrupt
    result = compiled.invoke({ amount: 5000 }, config: { thread_id: "t2" })
    assert result.is_a?(LangraphRuby::Execution::InterruptResult)
    assert_equal :check, result.interrupted_node
    assert_equal({ reason: "High value transfer", amount: 5000 }, result.interrupt_value)
  end

  def test_dynamic_interrupt_resume_with_value
    call_count = 0
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:review, ->(s) {
      call_count += 1
      if call_count == 1
        LangraphRuby.interrupt("Please review this draft")
      end
      # On resume, read the resume value from state
      approval = s[:__resume_value__]
      { approved: approval == "yes", review_count: call_count }
    })
    g.add_edge(LangraphRuby::START, :review)
    g.add_edge(:review, LangraphRuby::END_)

    compiled = g.compile(checkpointer: @checkpointer)

    # First call — interrupts
    result = compiled.invoke({}, config: { thread_id: "t1" })
    assert result.is_a?(LangraphRuby::Execution::InterruptResult)
    assert_equal "Please review this draft", result.interrupt_value

    # Resume with approval
    final = compiled.invoke(nil, config: { thread_id: "t1", resume: "yes" })
    assert_equal true, final[:approved]
    assert_equal 2, final[:review_count]
  end

  def test_interrupt_without_checkpointer_still_returns_result
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:node, ->(s) { LangraphRuby.interrupt("pause") })
    g.add_edge(LangraphRuby::START, :node)
    g.add_edge(:node, LangraphRuby::END_)

    compiled = g.compile  # no checkpointer
    result = compiled.invoke({})
    assert result.is_a?(LangraphRuby::Execution::InterruptResult)
    assert_equal "pause", result.interrupt_value
  end
end
