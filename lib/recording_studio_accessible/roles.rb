# frozen_string_literal: true

require "recording_studio_accessible/role_set"

module RecordingStudioAccessible
  # Direct-grant names for the target recording. Ancestor grants stay out of this check.
  module Roles
    module_function

    def names_for(recording)
      role_set_for(recording).names
    end

    def allowed?(recording, role)
      role_set_for(recording).include?(role)
    end

    def role_set_for(recording)
      klass = recordable_class(recording)
      return RoleSet.default unless klass.respond_to?(:accessible_role_set)

      klass.accessible_role_set
    end

    def recordable_class(recording)
      return if recording.nil?

      return recording.recordable.class if recording.respond_to?(:recordable) && recording.recordable

      return unless recording.respond_to?(:recordable_type)

      type_name = recording.recordable_type.to_s
      return if type_name.empty?

      type_name.safe_constantize
    end
  end
end
