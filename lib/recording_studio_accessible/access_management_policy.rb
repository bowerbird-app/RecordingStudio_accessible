# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessManagementPolicy
    class << self
      def allowed?(recording:, actor: nil, controller: nil)
        RecordingStudioAccessible.configuration.authorize_access_management?(
          recording: recording,
          actor: actor,
          controller: controller
        )
      end
    end
  end
end
