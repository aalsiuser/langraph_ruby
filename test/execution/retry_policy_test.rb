# frozen_string_literal: true

require "test_helper"

class RetryPolicyTest < Minitest::Test
  def test_succeeds_without_retry
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 3, initial_delay: 0)
    result = policy.execute { 42 }
    assert_equal 42, result
  end

  def test_retries_on_failure_then_succeeds
    attempts = 0
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 3, initial_delay: 0)
    result = policy.execute {
      attempts += 1
      raise "fail" if attempts < 3
      "success"
    }
    assert_equal "success", result
    assert_equal 3, attempts
  end

  def test_raises_after_max_retries
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 2, initial_delay: 0)
    assert_raises(RuntimeError) do
      policy.execute { raise "always fails" }
    end
  end

  def test_retry_on_filter
    policy = LangraphRuby::Execution::RetryPolicy.new(
      max_retries: 3,
      initial_delay: 0,
      retry_on: ->(e) { e.message.include?("transient") }
    )

    # Should retry transient errors
    attempts = 0
    result = policy.execute {
      attempts += 1
      raise "transient error" if attempts < 2
      "ok"
    }
    assert_equal "ok", result

    # Should not retry non-transient errors
    assert_raises(RuntimeError) do
      policy.execute { raise "permanent error" }
    end
  end

  def test_never_retries_graph_interrupt
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 3, initial_delay: 0)
    assert_raises(LangraphRuby::GraphInterrupt) do
      policy.execute { LangraphRuby.interrupt("stop") }
    end
  end

  def test_retry_in_graph_node
    attempts = 0
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 3, initial_delay: 0)

    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:flaky, ->(s) {
      attempts += 1
      raise "flaky error" if attempts < 3
      { result: "worked on attempt #{attempts}" }
    }, retry_policy: policy)
    g.add_edge(LangraphRuby::START, :flaky)
    g.add_edge(:flaky, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal "worked on attempt 3", result[:result]
    assert_equal 3, attempts
  end

  def test_retry_exhausted_in_graph_node
    policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 1, initial_delay: 0)

    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:broken, ->(s) { raise "always broken" }, retry_policy: policy)
    g.add_edge(LangraphRuby::START, :broken)
    g.add_edge(:broken, LangraphRuby::END_)

    compiled = g.compile
    assert_raises(LangraphRuby::GraphExecutionError) do
      compiled.invoke({})
    end
  end

  def test_default_policy_values
    policy = LangraphRuby::Execution::RetryPolicy.new
    assert_equal 3, policy.max_retries
    assert_equal 1.0, policy.initial_delay
    assert_equal 2.0, policy.backoff_factor
    assert_equal true, policy.jitter
  end
end
