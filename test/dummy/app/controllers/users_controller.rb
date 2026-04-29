class UsersController < ApplicationController
  def show
    @user = User.find(params[:id])
    @accessible_items = accessible_items_for(@user)
  end

  private

  def accessible_items_for(user)
    active_recordings.filter_map do |recording|
      next unless RecordingStudioAccessible.authorized?(actor: user, recording: recording, role: :view)

      {
        label: recordable_label_for(recording.recordable),
        recordable_type: recording.recordable_type.demodulize,
        role: RecordingStudioAccessible.role_for(actor: user, recording: recording),
        root_label: recordable_label_for(recording.root_recording&.recordable || recording.recordable)
      }
    end
  end

  def active_recordings
    RecordingStudio::Recording.unscoped
                             .where(trashed_at: nil)
                             .where.not(recordable_type: [ "RecordingStudio::Access" ])
                             .includes(:recordable, :root_recording)
                             .order(:created_at)
  end

  def recordable_label_for(recordable)
    return "Unknown" unless recordable
    return recordable.name if recordable.respond_to?(:name)
    return recordable.title if recordable.respond_to?(:title)

    recordable.class.name.demodulize
  end
end
