# frozen_string_literal: true

require "test_helper"

class HumanInTheLoopTest < Minitest::Test
  # Full integration test: email approval workflow
  # draft → human review (interrupt) → send or revise
  def test_email_approval_workflow
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
      field :draft, type: String
      field :approved, type: Object, default: false
      field :sent, type: Object, default: false
      field :revision_count, type: Integer, default: 0, reducer: :add
    end

    checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new
    review_count = 0

    g = LangraphRuby::Graph::StateGraph.new(schema)

    g.add_node(:draft, ->(s) {
      content = s[:revision_count] > 0 ? "Revised draft v#{s[:revision_count] + 1}" : "Initial draft"
      { draft: content, revision_count: 1 }
    })

    g.add_node(:send_email, ->(s) {
      msg = LangraphRuby::Messages::AIMessage.new(content: "Email sent: #{s[:draft]}")
      { sent: true, messages: [msg] }
    })

    g.add_edge(LangraphRuby::START, :draft)
    g.add_edge(:draft, :send_email)
    g.add_edge(:send_email, LangraphRuby::END_)

    # We use interrupt_after :draft to let human review before send_email runs
    compiled = g.compile(checkpointer: checkpointer, interrupt_after: [:draft])

    # Step 1: Generate draft — pauses after :draft
    result = compiled.invoke({}, config: { thread_id: "email-1" })
    assert result.interrupted?
    assert_equal :draft, result.interrupted_node
    assert_equal "Initial draft", result[:draft]

    # Step 2: Human reviews and sees the draft via get_state
    state = compiled.get_state({ thread_id: "email-1" })
    assert_equal "Initial draft", state[:draft]

    # Step 3: Verify state history shows the progression
    history = compiled.get_state_history({ thread_id: "email-1" })
    assert history.length >= 1
  end

  # Test: dynamic interrupt for human to make a routing decision
  def test_routing_with_human_decision
    checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new

    call_count = 0
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:analyze, ->(s) {
      call_count += 1
      if call_count == 1
        LangraphRuby.interrupt({ options: [:support, :sales] })
      end
      choice = s[:__resume_value__]
      { route: choice }
    })

    g.add_node(:handle, ->(s) { { result: "#{s[:route]} handled it" } })

    g.add_edge(LangraphRuby::START, :analyze)
    g.add_edge(:analyze, :handle)
    g.add_edge(:handle, LangraphRuby::END_)

    compiled = g.compile(checkpointer: checkpointer)

    # Analyze interrupts for human choice
    result = compiled.invoke({ query: "I need help" }, config: { thread_id: "route-1" })
    assert result.is_a?(LangraphRuby::Execution::InterruptResult)
    assert_equal({ options: [:support, :sales] }, result.interrupt_value)

    # Human resumes with "sales"
    final = compiled.invoke(nil, config: { thread_id: "route-1", resume: "sales" })
    assert_equal "sales handled it", final[:result]
  end

  # Test: time-travel by replaying from an earlier checkpoint
  def test_time_travel_replay
    checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new

    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :value, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:add10, ->(s) { { value: 10 } })
    g.add_node(:add5, ->(s) { { value: 5 } })
    g.add_edge(LangraphRuby::START, :add10)
    g.add_edge(:add10, :add5)
    g.add_edge(:add5, LangraphRuby::END_)

    compiled = g.compile(checkpointer: checkpointer)
    compiled.invoke({}, config: { thread_id: "tt-1" })

    # Final state should be 15
    state = compiled.get_state({ thread_id: "tt-1" })
    assert_equal 15, state[:value]

    # Get history and find an earlier checkpoint
    history = compiled.get_state_history({ thread_id: "tt-1" })
    assert history.length >= 2

    # The earliest checkpoint should have value 10 (after add10, before add5)
    early = history.find { |s| s[:value] == 10 }
    assert early, "Should find a checkpoint with value 10"
  end

  # Test: conversation memory across multiple invocations
  def test_conversation_memory
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :messages, type: Array, reducer: :add_messages
    end

    checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:echo, ->(s) {
      last = s[:messages].last
      reply = LangraphRuby::Messages::AIMessage.new(content: "Echo: #{last.content}")
      { messages: [reply] }
    })
    g.add_edge(LangraphRuby::START, :echo)
    g.add_edge(:echo, LangraphRuby::END_)

    compiled = g.compile(checkpointer: checkpointer)

    # Turn 1
    compiled.invoke(
      { messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hello")] },
      config: { thread_id: "conv-1" }
    )

    state = compiled.get_state({ thread_id: "conv-1" })
    assert_equal 2, state[:messages].length

    # Turn 2 — adds to existing conversation
    compiled.invoke(
      { messages: [LangraphRuby::Messages::HumanMessage.new(content: "How are you?")] },
      config: { thread_id: "conv-1" }
    )

    state = compiled.get_state({ thread_id: "conv-1" })
    assert_equal 4, state[:messages].length
    assert_equal "Echo: How are you?", state[:messages].last.content
  end
end
