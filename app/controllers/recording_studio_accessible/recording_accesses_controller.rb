# frozen_string_literal: true

module RecordingStudioAccessible
  class RecordingAccessesController < ApplicationController
    layout "recording_studio_accessible/blank"

    before_action :set_recording
    before_action :authorize_access_management!
    before_action :set_access_recording, only: %i[edit update destroy]
    before_action :prepare_index_page_state, only: [:index]
    before_action :prepare_new_page_state, only: %i[new create]
    before_action :prepare_edit_page_state, only: %i[edit update]

    def index; end

    def new; end

    def create
      result = RecordingStudioAccessible::Services::GrantRecordingAccess.call(
        recording: @recording,
        actor: selected_actor,
        role: access_params[:role],
        manager_actor: current_actor
      )

      if result.success?
        redirect_to recording_accesses_path(@recording)
      else
        @form_errors = result.errors.presence || Array(result.error)
        render :new, status: :unprocessable_entity
      end
    end

    def edit; end

    def update
      result = RecordingStudioAccessible::Services::UpdateRecordingAccess.call(
        recording: @recording,
        access_recording: @access_recording,
        role: access_params[:role],
        manager_actor: current_actor
      )

      if result.success?
        redirect_to recording_accesses_path(@recording)
      else
        @form_errors = result.errors.presence || Array(result.error)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      result = RecordingStudioAccessible::Services::RevokeRecordingAccess.call(
        recording: @recording,
        access_recording: @access_recording,
        manager_actor: current_actor
      )

      if result.success?
        redirect_to recording_accesses_path(@recording), notice: "Access removed."
      else
        head :unprocessable_entity
      end
    end

    private

    def set_recording
      @recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    end

    def authorize_access_management!
      return if RecordingStudioAccessible.configuration.authorize_access_management?(controller: self,
                                                                                     recording: @recording)

      head :forbidden
    end

    def prepare_index_page_state
      @direct_access_rows = build_direct_access_rows
      @inherited_access_rows = build_inherited_access_rows
      prepare_shared_page_state
    end

    def prepare_new_page_state
      @selected_email = access_params[:email].to_s.strip
      @selected_role = access_params[:role].presence || "view"
      @form_errors ||= []
      prepare_shared_page_state
    end

    def prepare_edit_page_state
      @selected_role = access_params[:role].presence || @access_recording.recordable.role
      @editing_actor_label = RecordingStudioAccessible.configuration.actor_label_for(@access_recording.recordable.actor)
      @editing_actor_type = @access_recording.recordable.actor.class.name.demodulize
      @form_errors ||= []
      prepare_shared_page_state
    end

    def prepare_shared_page_state
      @recording_label = RecordingStudio::Labels.title_for(@recording.recordable)
      @root_label = recordable_label_for((@recording.root_recording || @recording).recordable)
      @effective_role = effective_role_for(current_actor)
    end

    def access_params
      return {} unless params.key?(:access)

      params.require(:access).permit(:email, :role)
    end

    def current_actor
      return unless respond_to?(:current_user, true)

      send(:current_user)
    end

    def selected_actor
      email = access_params[:email].to_s.strip
      return if email.blank?

      RecordingStudioAccessible.configuration.resolve_actor_for_email(controller: self, email: email)
    end

    def set_access_recording
      @access_recording = direct_access_recordings.find(params[:id])
    end

    def build_direct_access_rows
      direct_access_recordings.map do |access_recording|
        actor = access_recording.recordable.actor

        {
          id: access_recording.id,
          actor_label: RecordingStudioAccessible.configuration.actor_label_for(actor),
          actor_type: actor.class.name.demodulize,
          direct_role: access_recording.recordable.role,
          effective_role: effective_role_for(actor)
        }
      end
    end

    def build_inherited_access_rows
      direct_actor_keys = build_actor_keys(direct_access_recordings)

      ancestor_access_recordings.each_with_object({}) do |access_recording, rows_by_actor|
        actor = access_recording.recordable.actor
        next unless actor

        actor_key = actor_key_for(actor)
        next if direct_actor_keys.include?(actor_key) || rows_by_actor.key?(actor_key)

        effective_role = effective_role_for(actor)
        next unless effective_role

        rows_by_actor[actor_key] = {
          actor_label: RecordingStudioAccessible.configuration.actor_label_for(actor),
          actor_type: actor.class.name.demodulize,
          source_label: recordable_label_for(access_recording.parent_recording&.recordable),
          source_role: access_recording.recordable.role,
          effective_role: effective_role
        }
      end.values
    end

    def direct_access_recordings
      @direct_access_recordings ||= RecordingStudio::Services::AccessCheck.access_recordings_for(@recording)
                                                                          .order(created_at: :asc, id: :asc)
    end

    def ancestor_access_recordings
      ancestor_recordings.flat_map do |recording|
        RecordingStudio::Services::AccessCheck.access_recordings_for(recording)
                                             .order(created_at: :asc, id: :asc)
      end
    end

    def ancestor_recordings
      @ancestor_recordings ||= begin
        ancestors = []
        current_recording = @recording.parent_recording

        while current_recording
          ancestors << current_recording
          current_recording = current_recording.parent_recording
        end

        ancestors
      end
    end

    def build_actor_keys(access_recordings)
      access_recordings.filter_map do |access_recording|
        actor = access_recording.recordable.actor
        actor_key_for(actor) if actor
      end.to_set
    end

    def actor_key_for(actor)
      [actor.class.base_class.name, actor.id]
    end

    def effective_role_for(actor)
      return unless actor

      RecordingStudio::Services::AccessCheck.role_for(actor: actor, recording: @recording)
    end

    def recordable_label_for(recordable)
      return "Unknown" unless recordable
      return recordable.recordable_name if recordable.respond_to?(:recordable_name)
      return recordable.name if recordable.respond_to?(:name)
      return recordable.title if recordable.respond_to?(:title)

      recordable.class.name.demodulize
    end

  end
end
