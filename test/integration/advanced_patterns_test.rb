# frozen_string_literal: true

require "test_helper"

class AdvancedPatternsTest < Minitest::Test
  # Multi-agent system: router → specialist subgraphs
  def test_multi_agent_with_subgraphs
    # Research agent subgraph
    research = LangraphRuby::Graph::StateGraph.new
    research.add_node(:search, ->(s) { { findings: "Research on: #{s[:topic]}" } })
    research.add_edge(LangraphRuby::START, :search)
    research.add_edge(:search, LangraphRuby::END_)

    # Writing agent subgraph
    writing = LangraphRuby::Graph::StateGraph.new
    writing.add_node(:write, ->(s) { { draft: "Article about #{s[:topic]}: #{s[:findings]}" } })
    writing.add_edge(LangraphRuby::START, :write)
    writing.add_edge(:write, LangraphRuby::END_)

    # Coordinator graph
    coordinator = LangraphRuby::Graph::StateGraph.new
    coordinator.add_node(:plan, ->(s) { { topic: s[:query] } })
    coordinator.add_node(:research, LangraphRuby::Graph::Subgraph.new(research.compile))
    coordinator.add_node(:write, LangraphRuby::Graph::Subgraph.new(writing.compile))
    coordinator.add_node(:review, ->(s) { { final: "Reviewed: #{s[:draft]}" } })

    coordinator.add_edge(LangraphRuby::START, :plan)
    coordinator.add_edge(:plan, :research)
    coordinator.add_edge(:research, :write)
    coordinator.add_edge(:write, :review)
    coordinator.add_edge(:review, LangraphRuby::END_)

    result = coordinator.compile.invoke({ query: "Ruby programming" })
    assert_match(/Ruby programming/, result[:final])
    assert_match(/Research on/, result[:final])
  end

  # Command-based multi-agent handoff
  def test_command_handoff
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:triage, ->(s) {
      target = s[:priority] == "high" ? :senior : :junior
      LangraphRuby::Execution::Command.new(
        goto: target,
        update: { triaged: true, assigned_to: target.to_s }
      )
    })
    g.add_node(:senior, ->(s) { { response: "Senior agent handled: #{s[:query]}" } })
    g.add_node(:junior, ->(s) { { response: "Junior agent handled: #{s[:query]}" } })

    g.add_edge(LangraphRuby::START, :triage)
    g.add_conditional_edges(:triage, ->(s) { :senior }) # placeholder
    g.add_edge(:senior, LangraphRuby::END_)
    g.add_edge(:junior, LangraphRuby::END_)

    compiled = g.compile

    # High priority → senior
    result = compiled.invoke({ query: "Critical issue", priority: "high" })
    assert_equal true, result[:triaged]
    assert_equal "senior", result[:assigned_to]
    assert_match(/Senior/, result[:response])

    # Low priority → junior
    result = compiled.invoke({ query: "Simple question", priority: "low" })
    assert_equal true, result[:triaged]
    assert_equal "junior", result[:assigned_to]
    assert_match(/Junior/, result[:response])
  end

  # Send-based parallel research
  def test_parallel_research_with_send
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :questions, type: Array, default: -> { [] }
      field :answers, type: Array, reducer: :append
      field :summary, type: String
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:dispatch, ->(s) {
      s[:questions].map do |q|
        LangraphRuby::Execution::Send.new(node: :research, state: { current_q: q })
      end
    })
    g.add_node(:research, ->(s) { { answers: ["Answer to: #{s[:current_q]}"] } })
    g.add_node(:summarize, ->(s) {
      { summary: "Found #{s[:answers].length} answers" }
    })

    g.add_edge(LangraphRuby::START, :dispatch)
    g.add_edge(:dispatch, :summarize)
    g.add_edge(:summarize, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({ questions: ["What is Ruby?", "What is Rails?", "What is YJIT?"] })
    assert_equal 3, result[:answers].length
    assert_equal "Found 3 answers", result[:summary]
  end

  # Iterative refinement with retry on flaky steps
  def test_retry_with_conditional_loop
    attempt_counts = Hash.new(0)
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 2, initial_delay: 0)

    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :draft, type: String, default: ""
      field :quality, type: Integer, default: 0
      field :iterations, type: Integer, default: 0, reducer: :add
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:generate, ->(s) {
      attempt_counts[:generate] += 1
      raise "API timeout" if attempt_counts[:generate] == 1
      iter = s[:iterations] + 1
      { draft: "Draft v#{iter}", quality: iter * 35, iterations: 1 }
    }, retry_policy: policy)

    g.add_node(:evaluate, ->(s) { {} }) # passthrough

    g.add_edge(LangraphRuby::START, :generate)
    g.add_edge(:generate, :evaluate)
    g.add_conditional_edges(:evaluate, ->(s) {
      s[:quality] >= 70 ? LangraphRuby::END_ : :generate
    })

    compiled = g.compile
    result = compiled.invoke({})
    assert result[:quality] >= 70
    assert_equal "Draft v2", result[:draft]
    # generate was called: 1 (fail, retried) + 1 (success) + 1 (success) = 3
    assert attempt_counts[:generate] >= 2
  end

  # Full pipeline: subgraph + command + checkpointing
  def test_full_pipeline_with_checkpointing
    checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new

    # Analysis subgraph
    analysis = LangraphRuby::Graph::StateGraph.new
    analysis.add_node(:analyze, ->(s) { { analysis: "Analyzed: #{s[:input]}" } })
    analysis.add_edge(LangraphRuby::START, :analyze)
    analysis.add_edge(:analyze, LangraphRuby::END_)

    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:preprocess, ->(s) { { input: s[:raw_input].upcase } })
    g.add_node(:analyze, LangraphRuby::Graph::Subgraph.new(analysis.compile))
    g.add_node(:decide, ->(s) {
      if s[:analysis].length > 20
        LangraphRuby::Execution::Command.new(goto: LangraphRuby::END_, update: { status: "complete" })
      else
        LangraphRuby::Execution::Command.new(goto: LangraphRuby::END_, update: { status: "too short" })
      end
    })

    g.add_edge(LangraphRuby::START, :preprocess)
    g.add_edge(:preprocess, :analyze)
    g.add_edge(:analyze, :decide)
    g.add_conditional_edges(:decide, ->(s) { LangraphRuby::END_ }) # placeholder

    compiled = g.compile(checkpointer: checkpointer)
    result = compiled.invoke({ raw_input: "hello world" }, config: { thread_id: "pipe-1" })

    assert_equal "HELLO WORLD", result[:input]
    assert_match(/Analyzed/, result[:analysis])
    assert_equal "complete", result[:status]

    # Verify checkpoints were saved
    history = compiled.get_state_history({ thread_id: "pipe-1" })
    assert history.length >= 2
  end
end
