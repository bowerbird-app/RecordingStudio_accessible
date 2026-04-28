# frozen_string_literal: true

module RecordingStudio
  module AccessRoles
    ORDER = { "view" => 0, "edit" => 1, "admin" => 2 }.freeze

    class << self
      def value_for(role)
        ORDER[normalize(role)]
      end

      def satisfies?(role:, minimum_role:)
        role_value = value_for(role)
        minimum_value = value_for(minimum_role)

        return false unless role_value && minimum_value

        role_value >= minimum_value
      end

      def normalize(role)
        role&.to_s
      end
    end
  end
end
