# frozen_string_literal: true

require "test_helper"

class ToolTest < Minitest::Test
  def test_creates_tool
    tool = LangraphRuby::Tools::Tool.new(
      name: "search",
      description: "Search the web"
    ) { |query:| "Results for: #{query}" }

    assert_equal "search", tool.name
    assert_equal "Search the web", tool.description
  end

  def test_call_tool
    tool = LangraphRuby::Tools::Tool.new(
      name: "add",
      description: "Add two numbers",
      parameters: {
        a: { type: "integer", description: "First number", required: true },
        b: { type: "integer", description: "Second number", required: true }
      }
    ) { |a:, b:| a + b }

    assert_equal 7, tool.call({ "a" => 3, "b" => 4 })
  end

  def test_call_with_symbol_keys
    tool = LangraphRuby::Tools::Tool.new(
      name: "greet",
      description: "Greet someone"
    ) { |name:| "Hello, #{name}!" }

    assert_equal "Hello, Ruby!", tool.call({ name: "Ruby" })
  end

  def test_tool_requires_block
    assert_raises(ArgumentError) do
      LangraphRuby::Tools::Tool.new(name: "bad", description: "no block")
    end
  end

  def test_to_schema
    tool = LangraphRuby::Tools::Tool.new(
      name: "search",
      description: "Search the web",
      parameters: {
        query: { type: "string", description: "Search query", required: true },
        limit: { type: "integer", description: "Max results" }
      }
    ) { |query:, limit: 10| "results" }

    schema = tool.to_schema
    assert_equal "search", schema[:name]
    assert_equal "Search the web", schema[:description]
    assert_equal "object", schema[:parameters][:type]
    assert_includes schema[:parameters][:required], "query"
    refute_includes schema[:parameters][:required], "limit"
  end

  def test_to_schema_strips_required_marker_from_properties
    tool = LangraphRuby::Tools::Tool.new(
      name: "search",
      description: "Search the web",
      parameters: { query: { type: "string", description: "Search query", required: true } }
    ) { |query:| "results" }

    properties = tool.to_schema[:parameters][:properties]

    # `required: true` is the DSL marker — strict JSON Schema validators
    # (OpenAI) reject it inside a property ("True is not of type 'array'").
    refute_includes properties[:query].keys, :required
    assert_equal "string", properties[:query][:type]
  end

  def test_to_schema_does_not_mutate_tool_parameters
    params = { query: { type: "string", required: true } }
    tool = LangraphRuby::Tools::Tool.new(name: "t", description: "d", parameters: params) { |query:| "x" }

    tool.to_schema

    assert params[:query][:required], "to_schema must not mutate the tool's own parameters"
  end
end
