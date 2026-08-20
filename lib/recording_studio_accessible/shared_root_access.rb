# frozen_string_literal: true

module RecordingStudioAccessible
  module SharedRootAccess
    GRANT_DENIED_MESSAGE = "Grant access on objects below a shared root, not on the shared root itself."

    module_function

    def target?(recording)
      return false unless defined?(::RecordingStudio)
      return false if recording.blank?

      RecordingStudio.shared_root?(recording)
    end
  end
end
