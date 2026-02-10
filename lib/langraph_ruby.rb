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

  START = :__start__
  END_ = :__end__
end
