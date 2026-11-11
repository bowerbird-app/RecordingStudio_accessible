# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessManagementHelper
    def recording_access_management_path(recording)
      recording_studio_accessible.recording_accesses_path(recording)
    end

    def recording_access_management_link(recording, label: nil, **)
      text = label.presence || RecordingStudioAccessible::AccessManagementCopy.resolve(
        recording: recording,
        controller: self
      ).text("manage.title")
      link_to(text, recording_access_management_path(recording), **)
    end
  end
end
