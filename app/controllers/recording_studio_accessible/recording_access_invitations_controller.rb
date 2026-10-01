# frozen_string_literal: true

module RecordingStudioAccessible
  class RecordingAccessInvitationsController < ApplicationController
    include RecordingStudioAccessible::NavigationUrlSafety

    layout "recording_studio_accessible/blank"

    before_action :set_recording
    before_action :ensure_access_children_enabled!
    before_action :authorize_access_management!
    before_action :set_invitation

    def destroy
      result = RecordingStudioAccessible.revoke_access_invitation(
        invitation: @invitation,
        manager_actor: current_actor
      )
      redirect_to_access_index(result)
    end

    def resend
      result = RecordingStudioAccessible.invite_access(
        recording: @recording,
        email: @invitation.email,
        role: @invitation.role,
        manager_actor: current_actor,
        controller: self
      )
      redirect_to_access_index(result)
    end

    private

    def set_recording
      @recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    end

    def set_invitation
      @invitation = RecordingStudioAccessible::AccessInvitation.where(recording_id: @recording.id).find(params[:id])
    end

    def authorize_access_management!
      return if RecordingStudioAccessible::AccessManagementPolicy.allowed?(
        recording: @recording,
        actor: current_actor,
        controller: self
      )

      head :forbidden
    end

    def ensure_access_children_enabled!
      return if RecordingStudioAccessible::Compatibility.access_management_allowed?(@recording)

      head :not_found
    end

    def redirect_to_access_index(result)
      if result.success?
        redirect_to recording_access_index_redirect_path, notice: result.value.notice
      else
        redirect_to recording_access_index_redirect_path, alert: result.error
      end
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end

    def recording_access_index_redirect_path
      recording_accesses_path(@recording, **recording_access_navigation_params)
    end

    def recording_access_navigation_params
      back_url = safe_local_navigation_url(params[:back_url], fallback: host_root_path)
      anchor_url = safe_local_navigation_url(params[:anchor_url], fallback: back_url)

      {
        back_url: back_url,
        anchor_url: anchor_url
      }
    end

    def host_root_path
      return main_app.root_path if respond_to?(:main_app) && main_app.respond_to?(:root_path)

      "/"
    end
  end
end
