# frozen_string_literal: true

require_relative "lib/langraph_ruby/version"

Gem::Specification.new do |spec|
  spec.name = "langraph_ruby"
  spec.version = LangraphRuby::VERSION
  spec.authors = ["Vamsi"]
  spec.summary = "Graph-based agent orchestration framework for Ruby"
  spec.description = "A Ruby implementation of graph-based LLM agent orchestration " \
                     "with typed state, conditional routing, cycles, and streaming. " \
                     "Inspired by LangGraph."
  spec.homepage = "https://github.com/vamsi/langraph_ruby"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1.0"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "zeitwerk", "~> 2.6"

  spec.metadata = {
    "homepage_uri" => spec.homepage,
    "source_code_uri" => spec.homepage,
    "rubygems_mfa_required" => "true"
  }
end
