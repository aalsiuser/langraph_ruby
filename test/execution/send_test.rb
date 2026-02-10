# frozen_string_literal: true

require "test_helper"

class SendTest < Minitest::Test
  def test_send_fan_out_map_reduce
    schema = Class.new(LangraphRuby::State::StateSchema) do
      field :items, type: Array, default: -> { [] }
      field :results, type: Array, reducer: :append
      field :done
    end

    g = LangraphRuby::Graph::StateGraph.new(schema)

    # Fan-out: dispatch each item to :process
    g.add_node(:dispatch, ->(s) {
      s[:items].map do |item|
        LangraphRuby::Execution::Send.new(node: :process, state: { current_item: item })
      end
    })

    # Process each item
    g.add_node(:process, ->(s) {
      { results: ["processed:#{s[:current_item]}"] }
    })

    g.add_node(:collect, ->(s) { { done: true } })

    g.add_edge(LangraphRuby::START, :dispatch)
    g.add_edge(:dispatch, :collect)
    g.add_edge(:collect, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({ items: ["a", "b", "c"] })

    assert_equal 3, result[:results].length
    assert_includes result[:results], "processed:a"
    assert_includes result[:results], "processed:b"
    assert_includes result[:results], "processed:c"
    assert_equal true, result[:done]
  end

  def test_send_single_dynamic_edge
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:router, ->(s) {
      [LangraphRuby::Execution::Send.new(node: :handler, state: { data: "dynamic" })]
    })
    g.add_node(:handler, ->(s) { { result: "handled #{s[:data]}" } })
    g.add_edge(LangraphRuby::START, :router)
    g.add_edge(:router, LangraphRuby::END_)
    g.add_edge(:handler, LangraphRuby::END_)

    compiled = g.compile
    result = compiled.invoke({})
    assert_equal "handled dynamic", result[:result]
  end

  def test_send_class_properties
    s = LangraphRuby::Execution::Send.new(node: :target, state: { x: 1 })
    assert_equal :target, s.node
    assert_equal({ x: 1 }, s.state)
    assert s.send?
  end
end
