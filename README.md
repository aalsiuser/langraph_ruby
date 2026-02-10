# LangraphRuby

Graph-based LLM agent orchestration framework for Ruby. Build stateful, multi-step AI workflows with conditional routing, cycles, human-in-the-loop, tool calling, and streaming.

Inspired by [LangGraph](https://github.com/langchain-ai/langgraph) (Python/JS).

## Installation

Add to your Gemfile:

```ruby
gem "langraph_ruby"
```

Or install directly:

```bash
gem install langraph_ruby
```

**Requirements:** Ruby >= 3.1.0

**Optional dependencies** (install as needed):

```ruby
gem "sqlite3", "~> 2.0"   # For SqliteCheckpointer
gem "openai"               # For OpenAI adapter
gem "anthropic"            # For Anthropic adapter
gem "ruby_llm"             # For RubyLLM adapter
```

## Quick Start

```ruby
require "langraph_ruby"

# 1. Define a graph
graph = LangraphRuby::Graph::StateGraph.new

# 2. Add nodes (functions that transform state)
graph.add_node(:greet, ->(state) {
  { greeting: "Hello, #{state[:name]}!" }
})

# 3. Connect nodes with edges
graph.add_edge(LangraphRuby::START, :greet)
graph.add_edge(:greet, LangraphRuby::END_)

# 4. Compile and run
app = graph.compile
result = app.invoke({ name: "Ruby" })
puts result[:greeting]  # => "Hello, Ruby!"
```

## Table of Contents

- [Core Concepts](#core-concepts)
- [State Management](#state-management)
- [Messages](#messages)
- [Conditional Routing](#conditional-routing)
- [Cycles and Loops](#cycles-and-loops)
- [Streaming](#streaming)
- [Tool Calling](#tool-calling)
- [LLM Adapters](#llm-adapters)
- [ReAct Agent](#react-agent)
- [Checkpointing and Persistence](#checkpointing-and-persistence)
- [Human-in-the-Loop](#human-in-the-loop)
- [Subgraphs](#subgraphs)
- [Command (Dynamic Routing)](#command-dynamic-routing)
- [Send (Fan-Out / Map-Reduce)](#send-fan-out--map-reduce)
- [Retry Policies](#retry-policies)
- [DSL Block Syntax](#dsl-block-syntax)
- [API Reference](#api-reference)

## Core Concepts

LangraphRuby models AI workflows as **directed graphs**:

- **Nodes** are functions `(state) -> update` that read state and return updates
- **Edges** define the flow between nodes
- **State** is a shared hash that accumulates updates as the graph executes
- `START` and `END_` are special pseudo-nodes marking graph entry and exit

```
START --> classify --> [weather, math, general] --> END_
```

### Building a Graph

```ruby
graph = LangraphRuby::Graph::StateGraph.new

# Nodes accept a callable (lambda, proc, or any object responding to #call)
graph.add_node(:step_a, ->(state) { { result: "processed" } })
graph.add_node(:step_b, ->(state) { { final: state[:result].upcase } })

# Edges define flow
graph.add_edge(LangraphRuby::START, :step_a)  # Entry point
graph.add_edge(:step_a, :step_b)               # A flows to B
graph.add_edge(:step_b, LangraphRuby::END_)    # B ends the graph

# Compile validates the graph and returns an executable
compiled = graph.compile
result = compiled.invoke({ input: "hello" })
```

## State Management

### Basic State (Hash)

Without a schema, state is a plain hash. Node return values are merged via `Hash#merge`:

```ruby
graph.add_node(:init, ->(s) { { count: 1 } })
graph.add_node(:increment, ->(s) { { count: s[:count] + 1 } })
```

### Typed State with Schemas

Define a schema for structured state with defaults, types, and reducers:

```ruby
class ConversationState < LangraphRuby::State::StateSchema
  field :messages,   type: Array,   reducer: :add_messages
  field :score,      type: Integer, default: 0, reducer: :add
  field :draft,      type: String,  default: ""
  field :metadata,   type: Hash,    reducer: :merge
  field :tags,       type: Array,   reducer: :append
end

graph = LangraphRuby::Graph::StateGraph.new(ConversationState)
```

You can also define schemas inline with anonymous classes:

```ruby
schema = Class.new(LangraphRuby::State::StateSchema) do
  field :messages, type: Array, reducer: :add_messages
  field :step_count, type: Integer, default: 0, reducer: :add
end

graph = LangraphRuby::Graph::StateGraph.new(schema)
```

### Built-in Reducers

Reducers control how node updates are merged into state:

| Reducer | Behavior | Example |
|---------|----------|---------|
| `:last_value` | Overwrites (default) | `"old" + "new"` = `"new"` |
| `:append` | Appends to array | `[1] + [2, 3]` = `[1, 2, 3]` |
| `:add` | Sums numbers | `5 + 3` = `8` |
| `:merge` | Merges hashes | `{a: 1} + {b: 2}` = `{a: 1, b: 2}` |
| `:add_messages` | Smart message list | Appends, updates by ID, removes via `RemoveMessage` |

### Custom Reducers

Pass a `Proc` for custom merge logic:

```ruby
field :items, type: Array, reducer: ->(old_val, new_val) {
  (old_val + new_val).uniq
}
```

## Messages

LangraphRuby provides typed message classes for conversational AI:

```ruby
# User input
human = LangraphRuby::Messages::HumanMessage.new(content: "What is Ruby?")

# System instructions
system = LangraphRuby::Messages::SystemMessage.new(content: "You are helpful.")

# AI response
ai = LangraphRuby::Messages::AIMessage.new(content: "Ruby is a programming language.")

# AI response with tool calls
tool_call = LangraphRuby::Messages::ToolCall.new(name: "search", args: { query: "Ruby" })
ai_with_tools = LangraphRuby::Messages::AIMessage.new(content: "", tool_calls: [tool_call])
ai_with_tools.has_tool_calls?  # => true

# Tool execution result
tool_result = LangraphRuby::Messages::ToolMessage.new(
  content: "Ruby is a dynamic language...",
  tool_call_id: tool_call.id,
  tool_name: "search"
)

# Remove a message by ID (used with :add_messages reducer)
remove = LangraphRuby::Messages::RemoveMessage.new(id: old_message.id)
```

All messages have auto-generated UUIDs and support equality by `id`.

## Conditional Routing

Route to different nodes based on state:

```ruby
graph.add_node(:classify, ->(s) {
  category = s[:query].match?(/weather/) ? :weather : :general
  { category: category }
})
graph.add_node(:weather, ->(s) { { answer: "It's sunny!" } })
graph.add_node(:general, ->(s) { { answer: "I can help with that." } })

graph.add_edge(LangraphRuby::START, :classify)

# Option 1: Condition returns a node name directly
graph.add_conditional_edges(:classify, ->(state) { state[:category] })

# Option 2: With explicit mapping
graph.add_conditional_edges(:classify, ->(state) { state[:category] },
  { weather: :weather, general: :general }
)

graph.add_edge(:weather, LangraphRuby::END_)
graph.add_edge(:general, LangraphRuby::END_)
```

## Cycles and Loops

Conditional edges can route back to earlier nodes, creating loops:

```ruby
schema = Class.new(LangraphRuby::State::StateSchema) do
  field :draft, type: String, default: ""
  field :score, type: Integer, default: 0
  field :iterations, type: Integer, default: 0, reducer: :add
end

graph = LangraphRuby::Graph::StateGraph.new(schema)
graph.add_node(:write, ->(s) {
  iter = s[:iterations] + 1
  { draft: "Draft v#{iter}", score: iter * 30, iterations: 1 }
})
graph.add_node(:evaluate, ->(s) { {} })  # passthrough

graph.add_edge(LangraphRuby::START, :write)
graph.add_edge(:write, :evaluate)
graph.add_conditional_edges(:evaluate, ->(s) {
  s[:score] >= 90 ? LangraphRuby::END_ : :write
})

result = graph.compile.invoke({})
# Loops until score >= 90: Draft v1 (30), Draft v2 (60), Draft v3 (90)
result[:draft]       # => "Draft v3"
result[:iterations]  # => 3
```

## Streaming

Stream execution step-by-step instead of waiting for completion:

```ruby
compiled = graph.compile

# Stream full state after each step
compiled.stream({ name: "Ruby" }, stream_mode: :values).each do |snapshot|
  puts "Step #{snapshot.step}: #{snapshot.values}"
  puts "Next: #{snapshot.next_nodes}"
end

# Stream only node updates
compiled.stream({ name: "Ruby" }, stream_mode: :updates).each do |update|
  puts "Node #{update[:node]} at step #{update[:step]}: #{update[:update]}"
end
```

## Tool Calling

### Defining Tools

```ruby
search_tool = LangraphRuby::Tools::Tool.new(
  name: "search",
  description: "Search the web for information",
  parameters: {
    query: { type: "string", description: "Search query", required: true }
  }
) { |query:| "Results for: #{query}" }

calculator = LangraphRuby::Tools::Tool.new(
  name: "calculator",
  description: "Perform arithmetic calculations",
  parameters: {
    expression: { type: "string", description: "Math expression", required: true }
  }
) { |expression:| eval(expression).to_s }
```

### ToolNode

`ToolNode` automatically executes tool calls from the last `AIMessage`:

```ruby
tool_node = LangraphRuby::Tools::ToolNode.new(
  tools: [search_tool, calculator],
  handle_errors: true  # Return errors as messages instead of raising
)

# Use in a graph
graph.add_node(:tools, tool_node)
```

Error handling strategies:

```ruby
# Raise on error (default)
ToolNode.new(tools: tools, handle_errors: false)

# Return error as ToolMessage content
ToolNode.new(tools: tools, handle_errors: true)

# Custom error handler
ToolNode.new(tools: tools, handle_errors: ->(error, tool_call) {
  "Tool #{tool_call.name} failed: #{error.message}"
})
```

## LLM Adapters

### Anthropic (Claude)

```ruby
adapter = LangraphRuby::Adapters::AnthropicAdapter.new(
  api_key: ENV["ANTHROPIC_API_KEY"]  # or uses ANTHROPIC_API_KEY env var
)

response = adapter.chat(
  messages: [
    LangraphRuby::Messages::HumanMessage.new(content: "Hello!")
  ],
  tools: [search_tool],
  model: "claude-sonnet-4-20250514",
  max_tokens: 4096
)
# => LangraphRuby::Messages::AIMessage
```

### OpenAI

```ruby
adapter = LangraphRuby::Adapters::OpenAiAdapter.new(
  api_key: ENV["OPENAI_API_KEY"]
)

response = adapter.chat(
  messages: [LangraphRuby::Messages::HumanMessage.new(content: "Hello!")],
  tools: [search_tool],
  model: "gpt-4o"
)
```

### RubyLLM (Multi-Provider)

```ruby
adapter = LangraphRuby::Adapters::RubyLlmAdapter.new(
  model: "claude-sonnet-4-20250514"
)
```

### Custom Adapters

Extend `BaseAdapter` for any LLM provider:

```ruby
class MyAdapter < LangraphRuby::Adapters::BaseAdapter
  def chat(messages:, tools: [], **config)
    # Convert messages, call your API, return AIMessage
    LangraphRuby::Messages::AIMessage.new(content: "response")
  end
end
```

## ReAct Agent

Create a complete ReAct (Reason + Act) agent in one line:

```ruby
adapter = LangraphRuby::Adapters::AnthropicAdapter.new
tools = [search_tool, calculator]

agent = LangraphRuby::Agents::ReactAgent.create(
  adapter: adapter,
  tools: tools,
  system_prompt: "You are a helpful assistant. Use tools when needed."
)

result = agent.invoke({
  messages: [
    LangraphRuby::Messages::HumanMessage.new(content: "What is 42 * 17?")
  ]
})

# The agent loops: think -> tool_call -> tool_result -> think -> respond
result[:messages].last.content  # => "42 * 17 = 714"
```

The ReAct agent internally builds this graph:

```
START --> agent --> [has tool calls?]
                      |           |
                     yes          no
                      |           |
                   tools        END_
                      |
                   agent  (loop back)
```

## Checkpointing and Persistence

Checkpointing saves graph state between executions, enabling multi-turn conversations and time-travel debugging.

### Memory Checkpointer

```ruby
checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new
compiled = graph.compile(checkpointer: checkpointer)

# Each thread_id maintains independent state
compiled.invoke({ messages: [msg1] }, config: { thread_id: "user-123" })
compiled.invoke({ messages: [msg2] }, config: { thread_id: "user-123" })

# Retrieve current state
state = compiled.get_state({ thread_id: "user-123" })
state[:messages]  # => [msg1, reply1, msg2, reply2]

# Browse state history
history = compiled.get_state_history({ thread_id: "user-123" })
history.each { |snapshot| puts "Step #{snapshot.step}: #{snapshot.values}" }

# Manually update state
compiled.update_state({ approved: true }, { thread_id: "user-123" })
```

### SQLite Checkpointer

For persistence across process restarts:

```ruby
checkpointer = LangraphRuby::Checkpointers::SqliteCheckpointer.new(
  db_path: "checkpoints.db"  # or ":memory:" for in-memory
)
compiled = graph.compile(checkpointer: checkpointer)

# Use the same thread_id across sessions
compiled.invoke(input, config: { thread_id: "session-abc" })

# Later, in a new process:
state = compiled.get_state({ thread_id: "session-abc" })

# Clean up
checkpointer.delete("session-abc")
checkpointer.close
```

## Human-in-the-Loop

Pause graph execution for human review, approval, or input.

### Interrupt Before/After a Node

```ruby
compiled = graph.compile(
  checkpointer: checkpointer,
  interrupt_before: [:send_email],  # Pause before this node runs
  interrupt_after: [:draft]         # Pause after this node completes
)

# Execution pauses and returns an InterruptResult
result = compiled.invoke({}, config: { thread_id: "review-1" })
result.interrupted?       # => true
result.interrupted_node   # => :draft
result.interrupt_kind     # => :after
result[:draft]            # => Access state values

# Resume execution (continues from where it paused)
final = compiled.invoke(nil, config: { thread_id: "review-1", resume: "approved" })
```

### Dynamic Interrupts

Nodes can interrupt themselves programmatically:

```ruby
graph.add_node(:analyze, ->(state) {
  if state[:confidence] < 0.8
    # Pause and ask human for guidance
    LangraphRuby.interrupt({ question: "Low confidence. Proceed?", options: ["yes", "no"] })
  end

  # If resumed, the resume value is in state[:__resume_value__]
  decision = state[:__resume_value__]
  { approved: decision == "yes" }
})
```

### Workflow Example: Email Approval

```ruby
checkpointer = LangraphRuby::Checkpointers::MemoryCheckpointer.new

graph = LangraphRuby::Graph::StateGraph.new(EmailSchema)
graph.add_node(:draft, ->(s) { { draft: "Dear customer..." } })
graph.add_node(:send, ->(s) { { sent: true } })
graph.add_edge(LangraphRuby::START, :draft)
graph.add_edge(:draft, :send)
graph.add_edge(:send, LangraphRuby::END_)

compiled = graph.compile(
  checkpointer: checkpointer,
  interrupt_after: [:draft]
)

# Step 1: Generate draft (pauses after)
result = compiled.invoke({}, config: { thread_id: "email-1" })
puts result[:draft]  # Human reviews the draft

# Step 2: Resume to send
final = compiled.invoke(nil, config: { thread_id: "email-1", resume: "approved" })
final[:sent]  # => true
```

## Subgraphs

Compose complex workflows by nesting graphs:

```ruby
# Build a child graph
research = LangraphRuby::Graph::StateGraph.new
research.add_node(:search, ->(s) { { findings: "Research on: #{s[:topic]}" } })
research.add_edge(LangraphRuby::START, :search)
research.add_edge(:search, LangraphRuby::END_)

# Use it as a node in a parent graph
parent = LangraphRuby::Graph::StateGraph.new
parent.add_node(:plan, ->(s) { { topic: s[:query] } })
parent.add_node(:research, LangraphRuby::Graph::Subgraph.new(research.compile))
parent.add_node(:summarize, ->(s) { { summary: "Summary: #{s[:findings]}" } })

parent.add_edge(LangraphRuby::START, :plan)
parent.add_edge(:plan, :research)
parent.add_edge(:research, :summarize)
parent.add_edge(:summarize, LangraphRuby::END_)

result = parent.compile.invoke({ query: "Ruby YJIT" })
result[:summary]  # => "Summary: Research on: Ruby YJIT"
```

### Input/Output Mapping

When parent and child use different key names:

```ruby
subgraph = LangraphRuby::Graph::Subgraph.new(
  child_graph.compile,
  input_map: { user_name: :name },           # parent :user_name -> child :name
  output_map: { greeting: :welcome_message }  # child :greeting -> parent :welcome_message
)

parent.add_node(:greet, subgraph)
result = parent.compile.invoke({ user_name: "Ruby" })
result[:welcome_message]  # => "Hello, Ruby!"
```

### Nested Subgraphs

Subgraphs can contain other subgraphs for deep composition:

```ruby
inner = build_graph { ... }      # value + 1
middle = build_graph { ... }     # uses inner, then * 2
outer = build_graph { ... }      # sets value, uses middle

result = outer.compile.invoke({})  # (3 + 1) * 2 = 8
```

## Command (Dynamic Routing)

`Command` lets a node simultaneously update state AND control routing:

```ruby
graph.add_node(:triage, ->(state) {
  target = state[:priority] == "high" ? :senior : :junior
  LangraphRuby::Execution::Command.new(
    goto: target,
    update: { triaged: true, assigned_to: target.to_s }
  )
})

graph.add_node(:senior, ->(s) { { response: "Senior handled it" } })
graph.add_node(:junior, ->(s) { { response: "Junior handled it" } })
```

Route to `END_` to finish execution early:

```ruby
LangraphRuby::Execution::Command.new(
  goto: LangraphRuby::END_,
  update: { done: true, reason: "Nothing to do" }
)
```

Route to multiple nodes for parallel execution:

```ruby
LangraphRuby::Execution::Command.new(
  goto: [:research, :write],
  update: { started: true }
)
```

## Send (Fan-Out / Map-Reduce)

`Send` enables dynamic parallel execution. Return an array of `Send` objects to fan out to a target node with different inputs:

```ruby
schema = Class.new(LangraphRuby::State::StateSchema) do
  field :items, type: Array, default: -> { [] }
  field :results, type: Array, reducer: :append
end

graph = LangraphRuby::Graph::StateGraph.new(schema)

# Fan-out: dispatch each item to :process
graph.add_node(:dispatch, ->(state) {
  state[:items].map do |item|
    LangraphRuby::Execution::Send.new(
      node: :process,
      state: { current_item: item }
    )
  end
})

# Process runs once per Send, each with its own state
graph.add_node(:process, ->(state) {
  { results: ["processed: #{state[:current_item]}"] }
})

graph.add_node(:collect, ->(s) { { summary: "Done: #{s[:results].length} items" } })

graph.add_edge(LangraphRuby::START, :dispatch)
graph.add_edge(:dispatch, :collect)
graph.add_edge(:collect, LangraphRuby::END_)

result = graph.compile.invoke({ items: ["a", "b", "c"] })
result[:results]  # => ["processed: a", "processed: b", "processed: c"]
```

## Retry Policies

Add automatic retry logic to nodes for handling transient failures:

```ruby
policy = LangraphRuby::Execution::RetryPolicy.new(
  max_retries: 3,        # Maximum retry attempts
  initial_delay: 1.0,    # Seconds before first retry
  backoff_factor: 2.0,   # Multiply delay after each retry (1s, 2s, 4s)
  jitter: true           # Add randomness to avoid thundering herd
)

graph.add_node(:api_call, ->(state) {
  # If this raises, it retries up to 3 times with backoff
  response = call_external_api(state[:query])
  { result: response }
}, retry_policy: policy)
```

### Selective Retry

Only retry specific errors:

```ruby
policy = LangraphRuby::Execution::RetryPolicy.new(
  max_retries: 3,
  initial_delay: 0.5,
  retry_on: ->(error) { error.message.include?("timeout") }
)
```

`GraphInterrupt` is never retried, even when `retry_on` would match.

### Standalone Usage

`RetryPolicy` can be used independently outside of graphs:

```ruby
policy = LangraphRuby::Execution::RetryPolicy.new(max_retries: 3, initial_delay: 0)
result = policy.execute { call_flaky_api() }
```

## DSL Block Syntax

Build graphs with a more compact block-based DSL:

```ruby
compiled = LangraphRuby::Graph::StateGraph.new do
  node :greet, ->(s) { { greeting: "Hello, #{s[:name]}!" } }
  edge LangraphRuby::START => :greet
  edge :greet => LangraphRuby::END_
end.compile

result = compiled.invoke({ name: "World" })
```

## API Reference

### `LangraphRuby::Graph::StateGraph`

| Method | Description |
|--------|-------------|
| `new(schema = nil, &block)` | Create a graph, optionally with a state schema |
| `add_node(name, callable, retry_policy: nil)` | Add a named node |
| `add_edge(source, target)` | Add a direct edge between nodes |
| `add_conditional_edges(source, condition, mapping = nil)` | Add conditional routing |
| `compile(checkpointer:, interrupt_before:, interrupt_after:)` | Compile into an executable graph |

### `LangraphRuby::Execution::CompiledGraph`

| Method | Description |
|--------|-------------|
| `invoke(input, config: {})` | Execute graph to completion |
| `stream(input, config: {}, stream_mode: :values)` | Stream execution step-by-step |
| `get_state(config)` | Get current state for a thread |
| `get_state_history(config)` | Get full checkpoint history |
| `update_state(updates, config)` | Manually update thread state |

**Config options:** `thread_id`, `resume`, `checkpoint_id`, `max_steps` (default 25)

### `LangraphRuby::State::StateSchema`

| Method | Description |
|--------|-------------|
| `field(name, type:, default:, reducer:)` | Define a state field |
| `build_initial_state` | Create state with defaults |
| `apply_update(state, updates)` | Apply updates using reducers |

### `LangraphRuby::Graph::Subgraph`

| Method | Description |
|--------|-------------|
| `new(compiled_graph, input_map: nil, output_map: nil)` | Wrap a compiled graph as a node |
| `call(state)` | Execute the subgraph (callable interface) |

### `LangraphRuby::Execution::Command`

| Method | Description |
|--------|-------------|
| `new(goto:, update: {})` | Create a routing command |
| `goto` | Target node(s) as array of symbols |
| `update` | State update hash |

### `LangraphRuby::Execution::Send`

| Method | Description |
|--------|-------------|
| `new(node:, state: {})` | Create a send directive |
| `node` | Target node symbol |
| `state` | State to merge for this invocation |

### `LangraphRuby::Execution::RetryPolicy`

| Method | Description |
|--------|-------------|
| `new(max_retries:, initial_delay:, backoff_factor:, jitter:, retry_on:)` | Configure retry behavior |
| `execute(&block)` | Execute block with retry logic |

### `LangraphRuby::Tools::Tool`

| Method | Description |
|--------|-------------|
| `new(name:, description:, parameters: {}, &block)` | Define a tool |
| `call(args)` | Execute the tool |
| `to_schema` | Export as JSON Schema for LLM providers |

### `LangraphRuby::Tools::ToolNode`

| Method | Description |
|--------|-------------|
| `new(tools:, handle_errors: false)` | Create a tool executor node |
| `call(state)` | Execute tool calls from last AIMessage |

### `LangraphRuby::Agents::ReactAgent`

| Method | Description |
|--------|-------------|
| `create(adapter:, tools:, system_prompt:, state_schema:)` | Build a ReAct agent graph |

### Constants

| Constant | Value | Description |
|----------|-------|-------------|
| `LangraphRuby::START` | `:__start__` | Graph entry point |
| `LangraphRuby::END_` | `:__end__` | Graph exit point |

### Error Classes

| Error | Description |
|-------|-------------|
| `LangraphRuby::Error` | Base error class |
| `GraphCompilationError` | Invalid graph structure |
| `GraphExecutionError` | Runtime execution failure |
| `InvalidStateError` | Invalid state operation |
| `MaxStepsReachedError` | Exceeded max execution steps |
| `GraphInterrupt` | Raised by `LangraphRuby.interrupt` for human-in-the-loop |

## Testing

```bash
bundle exec rake test
```

## License

MIT License. See [LICENSE](LICENSE) for details.