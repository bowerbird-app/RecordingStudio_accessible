# frozen_string_literal: true

require "recording_studio_accessible/role_registry"

module RecordingStudioAccessible
  module RoleDeclaration
    def accessible_roles(*names)
      @accessible_role_set = RoleSet.declare(names)
      RoleRegistry.register(self)
    end

    def clear_accessible_roles!
      remove_instance_variable(:@accessible_role_set) if instance_variable_defined?(:@accessible_role_set)
      RoleRegistry.forget(self)
    end

    def accessible_role_set
      if instance_variable_defined?(:@accessible_role_set)
        @accessible_role_set
      elsif superclass.respond_to?(:accessible_role_set)
        superclass.accessible_role_set
      else
        RoleSet.default
      end
    end
  end
end
