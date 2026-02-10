# frozen_string_literal: true

require "zeitwerk"

loader = Zeitwerk::Loader.for_gem
loader.inflector.inflect(
  "ai_message" => "AIMessage",
  "openai_adapter" => "OpenAiAdapter",
  "ruby_llm_adapter" => "RubyLlmAdapter"
)
loader.setup

module LangraphRuby
  class Error < StandardError; end
  class GraphCompilationError < Error; end
  class GraphExecutionError < Error; end
  class InvalidStateError < Error; end
  class MaxStepsReachedError < Error; end

  # Raised by nodes to pause execution for human input
  class GraphInterrupt < Error
    attr_reader :value

    def initialize(value = nil)
      @value = value
      super("Graph interrupted")
    end
  end

  START = :__start__
  END_ = :__end__

  # Convenience method for nodes to trigger an interrupt
  # When resumed, returns the value provided by the human
  def self.interrupt(value = nil)
    raise GraphInterrupt.new(value)
  end
end
