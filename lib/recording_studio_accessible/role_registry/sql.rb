# frozen_string_literal: true

module RecordingStudioAccessible
  # Rank CASE expressions. The three built-in branches stay until a type
  # declares a custom role. After that, the grant recording's type picks the rank.
  module RoleSql
    module_function

    def rank_case(connection, role_sql, type_sql, ranks, declarations)
      return builtin_case(connection, role_sql, ranks) if type_sql.nil?

      typed_case(connection, role_sql, type_sql, ranks, declarations)
    end

    def minimum_case(connection, name, type_sql, ranks, declarations)
      return Integer(ranks[name]).to_s if type_sql.nil?

      typed_minimum(connection, name, type_sql, ranks, declarations)
    end

    def builtin_case(connection, role_sql, ranks)
      branches = RoleRegistry::BUILT_INS.filter_map do |built_in|
        rank = ranks[built_in]
        next unless rank

        "WHEN #{connection.quote(built_in)} THEN #{rank}"
      end
      "CASE #{role_sql} #{branches.join(' ')} END"
    end

    def typed_case(connection, role_sql, type_sql, ranks, declarations)
      branches = declarations.map do |type_name, names|
        pairs = names.map { |name| [name, ranks.fetch(name)] }
        type_branch(connection, role_sql, type_sql, type_name, pairs)
      end
      "CASE #{branches.join(' ')} ELSE #{builtin_case(connection, role_sql, ranks)} END"
    end

    def type_branch(connection, role_sql, type_sql, type_name, pairs)
      inner = pairs.map { |name, rank| "WHEN #{connection.quote(name)} THEN #{rank}" }
      "WHEN #{type_sql} = #{connection.quote(type_name)} THEN CASE #{role_sql} #{inner.join(' ')} END"
    end

    def typed_minimum(connection, name, type_sql, ranks, declarations)
      branches = declarations.map do |type_name, names|
        value = names.include?(name) ? ranks.fetch(name).to_s : "NULL"
        "WHEN #{type_sql} = #{connection.quote(type_name)} THEN #{value}"
      end
      fallback = RoleRegistry::BUILT_INS.include?(name) ? ranks.fetch(name).to_s : "NULL"
      "CASE #{branches.join(' ')} ELSE #{fallback} END"
    end
  end
end
