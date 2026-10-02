# frozen_string_literal: true

module RecordingStudioAccessible
  class RoleSet
    DEFAULT_NAMES = %w[view edit admin].freeze

    class << self
      def default
        @default ||= new(DEFAULT_NAMES)
      end

      def declare(names)
        list = Array(names).flatten
        raise ArgumentError, "accessible_roles requires at least one role" if list.empty?

        normalized = list.map { |name| name.to_s.strip }
        raise ArgumentError, "accessible_roles rejects a blank role" if normalized.any?(&:empty?)
        raise ArgumentError, "accessible_roles rejects duplicate roles" if normalized.uniq.length != normalized.length

        new(normalized)
      end
    end

    def initialize(names)
      @names = names.freeze
    end

    def names
      @names.dup
    end

    def include?(role)
      @names.include?(role.to_s.strip)
    end
  end
end
