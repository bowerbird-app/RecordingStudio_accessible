# frozen_string_literal: true

require "recording_studio_accessible/extracted/recording_studio/access_roles"

module RecordingStudio
  module Services
    class AccessBoundaryPolicy
      def initialize(minimum_role:, inherited_role:)
        @minimum_role = minimum_role
        @inherited_role = inherited_role
      end

      def resolved_role
        return nil if @minimum_role.blank? || @inherited_role.blank?

        return @inherited_role if RecordingStudio::AccessRoles.satisfies?(role: @inherited_role,
                                                                          minimum_role: @minimum_role)

        nil
      end
    end
  end
end
