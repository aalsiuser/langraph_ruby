# frozen_string_literal: true

module LangraphRuby
  module State
    class StateSchema
      FieldDef = Struct.new(:name, :type, :default, :reducer, keyword_init: true)

      class << self
        def fields
          @fields ||= {}
        end

        def field(name, type: nil, default: nil, reducer: nil)
          name = name.to_sym
          reducer = resolve_reducer(reducer)
          fields[name] = FieldDef.new(name: name, type: type, default: default, reducer: reducer)
        end

        def build_initial_state
          fields.each_with_object({}) do |(name, field_def), state|
            state[name] = if field_def.default.respond_to?(:call)
                            field_def.default.call
                          elsif field_def.default.nil? && field_def.type == Array
                            []
                          elsif field_def.default.nil? && field_def.type == Hash
                            {}
                          else
                            field_def.default
                          end
          end
        end

        def apply_update(current_state, updates)
          new_state = current_state.dup
          updates.each do |key, value|
            key = key.to_sym
            field_def = fields[key]
            next unless field_def

            if field_def.reducer
              new_state[key] = field_def.reducer.call(new_state[key], value)
            else
              new_state[key] = value
            end
          end
          new_state
        end

        def inherited(subclass)
          super
          subclass.instance_variable_set(:@fields, fields.dup)
        end

        private

        def resolve_reducer(reducer)
          case reducer
          when :add_messages then Reducers::ADD_MESSAGES
          when :append then Reducers::APPEND
          when :add then Reducers::ADD
          when :merge then Reducers::MERGE
          when :last_value then Reducers::LAST_VALUE
          when Proc, Method then reducer
          when nil then nil
          else
            raise ArgumentError, "Unknown reducer: #{reducer.inspect}"
          end
        end
      end
    end
  end
end
