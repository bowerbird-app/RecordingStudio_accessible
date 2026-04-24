# frozen_string_literal: true

module RecordingStudioAccessible
  module AccessManagementHelper
    def recording_access_management_path(recording)
      recording_studio_accessible.recording_accesses_path(recording)
    end

    def recording_access_management_link(recording, label: "Manage access", **)
      link_to(label, recording_access_management_path(recording), **)
    end
  end
end
