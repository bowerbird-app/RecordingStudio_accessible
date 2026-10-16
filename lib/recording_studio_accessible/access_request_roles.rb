# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessRequestRoles
    module_function

    def options_for(recording:, action: nil, manager: nil)
      RoleCeiling.cap(candidate_names(recording, action), recording: recording, manager: manager)
    end

    def allowed?(recording:, action:, role:, manager: nil)
      name = role.to_s.strip
      name.present? && options_for(recording: recording, action: action, manager: manager).include?(name)
    end

    def candidate_names(recording, action)
      allowed = RecordingStudioAccessible.roles_for(recording).map(&:to_s)
      granted = granted_for(action) & allowed
      granted.presence || allowed
    end

    def default_for(recording:, action: nil, suggested: nil, manager: nil)
      options = options_for(recording: recording, action: action, manager: manager)
      suggestion = suggested.to_s
      return suggestion if suggestion.present? && options.include?(suggestion)

      options.first
    end

    def granted_for(action)
      return [] if action.blank?

      Array(RecordingStudioAccessible.granted_roles_for(action)).filter_map { |role| role.to_s.strip.presence }
    end
  end
end
