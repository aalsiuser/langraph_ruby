# frozen_string_literal: true

require "test_helper"

class CommandTest < Minitest::Test
  def test_command_routes_to_specific_node
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:router, ->(s) {
      target = s[:input].include?("urgent") ? :fast : :slow
      LangraphRuby::Execution::Command.new(goto: target, update: { routed: true })
    })
    g.add_node(:fast, ->(s) { { result: "fast path" } })
    g.add_node(:slow, ->(s) { { result: "slow path" } })

    g.add_edge(LangraphRuby::START, :router)
    # No static edges from router — Command handles routing
    g.add_conditional_edges(:router, ->(s) { :fast }) # placeholder for validation
    g.add_edge(:fast, LangraphRuby::END_)
    g.add_edge(:slow, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({ input: "urgent request" })
    assert_equal true, result[:routed]
    assert_equal "fast path", result[:result]
  end

  def test_command_routes_to_end
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:check, ->(s) {
      LangraphRuby::Execution::Command.new(
        goto: LangraphRuby::END_,
        update: { done: true, reason: "nothing to do" }
      )
    })
    g.add_edge(LangraphRuby::START, :check)
    g.add_conditional_edges(:check, ->(s) { LangraphRuby::END_ }) # placeholder

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal true, result[:done]
    assert_equal "nothing to do", result[:reason]
  end

  def test_command_with_state_update
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :count, type: Integer, default: 0, reducer: :add
      field :route, type: String
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)
    g.add_node(:step, ->(s) {
      LangraphRuby::Execution::Command.new(
        goto: :finish,
        update: { count: 10, route: "via command" }
      )
    })
    g.add_node(:finish, ->(s) { { count: 1 } })
    g.add_edge(LangraphRuby::START, :step)
    g.add_conditional_edges(:step, ->(s) { :finish }) # placeholder
    g.add_edge(:finish, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal 11, result[:count]  # 10 from command + 1 from finish
    assert_equal "via command", result[:route]
  end

  def test_command_class_properties
    cmd = LangraphRuby::Execution::Command.new(goto: :target, update: { a: 1 })
    assert_equal [:target], cmd.goto
    assert_equal({ a: 1 }, cmd.update)
    assert cmd.command?
  end

  def test_command_multiple_targets
    cmd = LangraphRuby::Execution::Command.new(goto: [:a, :b], update: {})
    assert_equal [:a, :b], cmd.goto
  end
end
