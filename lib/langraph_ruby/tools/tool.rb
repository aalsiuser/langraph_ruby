# frozen_string_literal: true

module LangraphRuby
  module Tools
    class Tool
      attr_reader :name, :description, :parameters, :function

      # @param name [String] Tool name matching what the LLM will call
      # @param description [String] Description for the LLM to understand when to use this tool
      # @param parameters [Hash] JSON Schema-style parameter definitions
      # @param function [Proc] The callable that executes the tool
      def initialize(name:, description:, parameters: {}, &block)
        @name = name.to_s
        @description = description
        @parameters = parameters
        @function = block
        raise ArgumentError, "Tool '#{@name}' requires a block" unless @function
      end

      def call(args = {})
        @function.call(**symbolize_keys(args))
      end

      # Converts to the common tool schema format used by LLM providers
      def to_schema
        {
          name: @name,
          description: @description,
          parameters: {
            type: "object",
            # :required is this DSL's per-property marker, not a JSON Schema
            # property keyword — leaking it into properties makes strict
            # validators (e.g. OpenAI) reject the schema with
            # "True is not of type 'array'". Emit it only as the object-level
            # required array.
            properties: @parameters.transform_values { |v| v.except(:required) },
            required: @parameters.select { |_, v| v[:required] }.keys.map(&:to_s)
          }
        }
      end

      private

      def symbolize_keys(hash)
        return {} unless hash.is_a?(Hash)

        hash.each_with_object({}) do |(k, v), result|
          result[k.to_sym] = v
        end
      end
    end
  end
end
