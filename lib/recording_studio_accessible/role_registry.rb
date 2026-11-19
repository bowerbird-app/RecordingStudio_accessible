# frozen_string_literal: true

require_relative "role_registry/lookup"
require_relative "role_registry/order"
require_relative "role_registry/sql"

module RecordingStudioAccessible
  # One rank for every role name, built from accessible_roles declarations.
  #
  # Declaration order is weakest to strongest. view, edit, and admin keep that
  # order. A second type that reverses a pair raises at declaration. A role is
  # ranked on a recording only when that recording's type lists it. The rank
  # number is shared, so an edit grant and a download grant compare without
  # reading a row. Callers ask the registry. They do not recompute the order.
  class RoleRegistry
    BUILT_INS = %w[view edit admin].freeze

    class << self
      include RoleLookup

      def register(klass)
        names = klass.accessible_role_set.names
        remember(klass, names)
      end

      def forget(klass)
        declarations.delete(klass.name) if klass.name.present?
        rebuild_ranks!
      end

      def rescan!
        fresh = {}
        each_declared_class do |klass|
          fresh[klass.name] = klass.accessible_role_set.names
        end
        @declarations = fresh
        rebuild_ranks!
      end

      def custom?
        declarations.any?
      end

      def global_rank(role)
        ranks[normalize(role)]
      end

      def rank_on(recording, role)
        name = normalize(role)
        return if name.blank?
        return unless names_for(recording).include?(name)

        ranks[name]
      end

      def declares?(recording, role)
        names_for(recording).include?(normalize(role))
      end

      def custom_name?(role)
        name = normalize(role)
        name.present? && BUILT_INS.exclude?(name)
      end

      def names_at_or_above(minimum_role)
        floor = global_rank(minimum_role)
        return [] unless floor

        ranks.select { |_name, rank| rank >= floor }.keys
      end

      def meets?(recording, role, minimum_role)
        role_rank = rank_on(recording, role)
        minimum_rank = rank_on(recording, minimum_role)
        return false unless role_rank && minimum_rank

        role_rank >= minimum_rank
      end

      def types_declaring(role)
        name = normalize(role)
        declarations.select { |_type, names| names.include?(name) }.keys
      end

      def rank_sql(connection, role_sql, type_sql = nil)
        return RoleSql.builtin_case(connection, role_sql, ranks) unless custom?
        raise ArgumentError, "ranked custom roles need the grant recording type" if type_sql.nil?

        RoleSql.typed_case(connection, role_sql, type_sql, ranks, declarations)
      end

      def minimum_sql(connection, role, type_sql = nil)
        return Integer(global_rank(role)).to_s unless custom?
        raise ArgumentError, "ranked custom roles need the grant recording type" if type_sql.nil?

        RoleSql.typed_minimum(connection, normalize(role), type_sql, ranks, declarations)
      end

      def reset!
        @declarations = {}
        @ranks = nil
      end

      private

      def remember(klass, names)
        order_from(candidate_lists(klass, names))
        declarations[klass.name] = names if klass.name.present?
        rebuild_ranks!
      end

      def candidate_lists(klass, names)
        lists = declarations.dup
        lists[klass.name.presence || ["check", names]] = names
        lists.values
      end

      def declarations
        @declarations ||= {}
      end

      def ranks
        @ranks ||= order_from(declarations.values)
      end

      def order_from(lists)
        RoleOrder.ranks(lists)
      end

      def rebuild_ranks!
        @ranks = order_from(declarations.values)
      end

      def normalize(role)
        role.to_s.strip
      end
    end
  end
end
