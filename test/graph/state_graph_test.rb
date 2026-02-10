# frozen_string_literal: true

require "test_helper"

class StateGraphTest < Minitest::Test
  def test_add_node
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:greet, ->(state) { { output: "hi" } })
    assert g.nodes.key?(:greet)
  end

  def test_add_node_with_block
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:greet) { |state| { output: "hi" } }
    assert g.nodes.key?(:greet)
  end

  def test_duplicate_node_raises
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:greet, ->(s) { s })
    assert_raises(LangraphRuby::GraphCompilationError) do
      g.add_node(:greet, ->(s) { s })
    end
  end

  def test_reserved_node_name_raises
    g = LangraphRuby::Graph::StateGraph.new
    assert_raises(LangraphRuby::GraphCompilationError) do
      g.add_node(LangraphRuby::START, ->(s) { s })
    end
  end

  def test_add_edge
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { s })
    g.add_node(:b, ->(s) { s })
    g.add_edge(LangraphRuby::START, :a)
    g.add_edge(:a, :b)
    g.add_edge(:b, LangraphRuby::END_)
    assert_equal :a, g.edges[LangraphRuby::START]
    assert_equal :b, g.edges[:a]
    assert_equal LangraphRuby::END_, g.edges[:b]
  end

  def test_duplicate_edge_from_same_source_raises
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { s })
    g.add_node(:b, ->(s) { s })
    g.add_edge(:a, :b)
    assert_raises(LangraphRuby::GraphCompilationError) do
      g.add_edge(:a, LangraphRuby::END_)
    end
  end

  def test_add_conditional_edges
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:router, ->(s) { s })
    g.add_node(:a, ->(s) { s })
    g.add_node(:b, ->(s) { s })
    g.add_conditional_edges(:router, ->(s) { s[:choice] }, { yes: :a, no: :b })
    assert g.conditional_edges.key?(:router)
  end

  def test_compile_validates_no_nodes
    g = LangraphRuby::Graph::StateGraph.new
    assert_raises(LangraphRuby::GraphCompilationError) { g.compile }
  end

  def test_compile_validates_start_edge
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { s })
    g.add_edge(:a, LangraphRuby::END_)
    assert_raises(LangraphRuby::GraphCompilationError) { g.compile }
  end

  def test_compile_validates_orphan_node
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { s })
    g.add_node(:orphan, ->(s) { s })
    g.add_edge(LangraphRuby::START, :a)
    g.add_edge(:a, LangraphRuby::END_)
    g.add_edge(:orphan, LangraphRuby::END_)
    assert_raises(LangraphRuby::GraphCompilationError) { g.compile }
  end

  def test_compile_success
    g = LangraphRuby::Graph::StateGraph.new
    g.add_node(:a, ->(s) { s })
    g.add_edge(LangraphRuby::START, :a)
    g.add_edge(:a, LangraphRuby::END_)
    compiled = g.compile
    assert_instance_of LangraphRuby::Execution::CompiledGraph, compiled
  end

  def test_dsl_block_construction
    g = LangraphRuby::Graph::StateGraph.new do
      node :a, ->(s) { s }
      node :b, ->(s) { s }
      edge LangraphRuby::START => :a
      edge :a => :b
      edge :b => LangraphRuby::END_
    end
    assert g.nodes.key?(:a)
    assert g.nodes.key?(:b)
    assert_equal :a, g.edges[LangraphRuby::START]
  end
end
