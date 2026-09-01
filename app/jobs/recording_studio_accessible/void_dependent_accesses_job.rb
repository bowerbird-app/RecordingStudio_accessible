# frozen_string_literal: true

require "active_job"

module RecordingStudioAccessible
  class VoidDependentAccessesJob < ActiveJob::Base
    queue_as :default

    def perform(manager_access_recording_id, moved: false)
      args = { manager_access_recording_id: manager_access_recording_id }
      args[:moved] = true if moved
      Services::VoidDependentAccesses.call(**args)
    end
  end
end
