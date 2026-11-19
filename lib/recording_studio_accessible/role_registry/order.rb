# frozen_string_literal: true

module RecordingStudioAccessible
  # Weakest-first order for one set of role lists.
  #
  # Ready custom roles are scheduled before ready built-ins, so a custom role
  # with no stronger neighbor stays below the next built-in. A reversed pair
  # never finishes and raises.
  module RoleOrder
    module_function

    def ranks(lists)
      nodes, edges = graph(lists)
      ordered = schedule(nodes, edges)
      conflict!(nodes, ordered) if ordered.size < nodes.size

      ordered.each_with_index.to_h
    end

    def graph(lists)
      nodes = Set.new(RoleRegistry::BUILT_INS)
      edges = Hash.new { |hash, key| hash[key] = Set.new }
      add_edges(edges, nodes, RoleRegistry::BUILT_INS)
      lists.each { |names| add_edges(edges, nodes, names) }
      [nodes, edges]
    end

    def add_edges(edges, nodes, names)
      names.each { |name| nodes << name }
      names.each_cons(2) { |weaker, stronger| edges[weaker] << stronger }
    end

    def schedule(nodes, edges)
      indegree = indegree_for(nodes, edges)
      ready = nodes.select { |name| indegree[name].zero? }.to_set
      ordered = []
      drain(ready, ordered, edges, indegree)
      ordered
    end

    def indegree_for(nodes, edges)
      counts = nodes.to_h { |name| [name, 0] }
      edges.each_value { |stronger_names| count_incoming(counts, stronger_names) }
      counts
    end

    def count_incoming(counts, stronger_names)
      stronger_names.each { |name| counts[name] += 1 if counts.key?(name) }
    end

    def drain(ready, ordered, edges, indegree)
      while ready.any?
        pick = ready.min_by { |name| schedule_key(name) }
        ready.delete(pick)
        ordered << pick
        release(edges[pick], ready, indegree)
      end
    end

    def release(stronger_names, ready, indegree)
      stronger_names.each do |stronger|
        indegree[stronger] -= 1
        ready << stronger if indegree[stronger].zero?
      end
    end

    def schedule_key(name)
      index = RoleRegistry::BUILT_INS.index(name)
      index ? [1, index] : [0, name]
    end

    def conflict!(nodes, ordered)
      left = (nodes - ordered.to_set).to_a.sort.join(", ")
      raise ArgumentError, "accessible_roles orders conflict (#{left})"
    end
  end
end
