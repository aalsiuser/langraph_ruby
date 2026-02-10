# frozen_string_literal: true

module LangraphRuby
  module Graph
    class StateGraph
      attr_reader :schema, :nodes, :edges, :conditional_edges, :retry_policies

      def initialize(schema = nil, &block)
        @schema = schema
        @nodes = {}
        @edges = {}
        @conditional_edges = {}
        @retry_policies = {}
        instance_eval(&block) if block_given?
      end

      def add_node(name, callable = nil, retry_policy: nil, &block)
        name = name.to_sym
        raise GraphCompilationError, "Node '#{name}' already exists" if @nodes.key?(name)
        raise GraphCompilationError, "Node name '#{name}' is reserved" if reserved_name?(name)

        func = callable || block
        raise ArgumentError, "Node '#{name}' requires a callable or block" unless func
        raise ArgumentError, "Node function must respond to #call" unless func.respond_to?(:call)

        @nodes[name] = func
        @retry_policies[name] = retry_policy if retry_policy
        self
      end

      def add_edge(source, target)
        source = source.to_sym
        target = target.to_sym
        validate_edge_endpoints(source, target)

        raise GraphCompilationError, "Node '#{source}' already has an outgoing edge" if @edges.key?(source)
        raise GraphCompilationError, "Node '#{source}' already has conditional edges" if @conditional_edges.key?(source)

        @edges[source] = target
        self
      end

      def add_conditional_edges(source, condition, mapping = nil)
        source = source.to_sym
        raise GraphCompilationError, "Node '#{source}' already has an outgoing edge" if @edges.key?(source)
        raise GraphCompilationError, "Node '#{source}' already has conditional edges" if @conditional_edges.key?(source)
        raise ArgumentError, "Condition must respond to #call" unless condition.respond_to?(:call)

        validate_node_exists(source) unless source == LangraphRuby::START

        if mapping
          mapping = mapping.transform_keys(&:to_sym).transform_values(&:to_sym)
          mapping.each_value { |target| validate_edge_target(target) }
        end

        @conditional_edges[source] = { condition: condition, mapping: mapping }
        self
      end

      def compile(checkpointer: nil, interrupt_before: [], interrupt_after: [])
        validate_graph!
        Execution::CompiledGraph.new(
          graph: self,
          checkpointer: checkpointer,
          interrupt_before: interrupt_before.map(&:to_sym),
          interrupt_after: interrupt_after.map(&:to_sym)
        )
      end

      # DSL-style helpers for block-based construction
      def node(name, callable = nil, retry_policy: nil, &block)
        add_node(name, callable, retry_policy: retry_policy, &block)
      end

      def edge(source_target_hash)
        source_target_hash.each { |s, t| add_edge(s, t) }
        self
      end

      private

      def reserved_name?(name)
        [LangraphRuby::START, LangraphRuby::END_].include?(name)
      end

      def validate_node_exists(name)
        return if name == LangraphRuby::START || name == LangraphRuby::END_
        raise GraphCompilationError, "Node '#{name}' does not exist" unless @nodes.key?(name)
      end

      def validate_edge_target(target)
        return if target == LangraphRuby::END_
        raise GraphCompilationError, "Target node '#{target}' does not exist" unless @nodes.key?(target)
      end

      def validate_edge_endpoints(source, target)
        validate_node_exists(source)
        validate_edge_target(target)
      end

      def validate_graph!
        raise GraphCompilationError, "Graph has no nodes" if @nodes.empty?

        # Must have a path from START
        start_edges = @edges[LangraphRuby::START] || @conditional_edges[LangraphRuby::START]
        raise GraphCompilationError, "Graph must have an edge from START" unless start_edges

        # Note: We don't require every node to have outgoing edges or be statically
        # reachable from START, because Send-targeted nodes are invoked dynamically
        # at runtime. The execution engine defaults to END_ for nodes without edges.
      end

    end
  end
end
