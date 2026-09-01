# frozen_string_literal: true

require "active_job"

module RecordingStudioAccessible
  class VoidDependentAccessesJob < ActiveJob::Base
    queue_as :default

    def perform(manager_access_recording_id)
      Services::VoidDependentAccesses.call(manager_access_recording_id: manager_access_recording_id)
    end
  end
end
