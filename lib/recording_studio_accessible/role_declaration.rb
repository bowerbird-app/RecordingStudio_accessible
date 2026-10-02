# frozen_string_literal: true

module RecordingStudioAccessible
  module RoleDeclaration
    def accessible_roles(*names)
      @accessible_role_set = RoleSet.declare(names)
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
