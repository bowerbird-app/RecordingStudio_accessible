# frozen_string_literal: true

require "uri"

module RecordingStudioAccessible
  class AccessInvitationsController < ApplicationController
    include RecordingStudioAccessible::NavigationUrlSafety

    layout "recording_studio_accessible/blank"

    skip_before_action :authenticate_user!, raise: false

    before_action :set_invitation

    def show
      return if redirect_unsigned_visitor?

      assign_show_state
    end

    def accept
      return if redirect_unsigned_visitor?

      actor = current_actor
      return render_sign_in_required if actor.blank?

      redirect_or_render_accept(actor)
    end

    private

    def set_invitation
      @invitation = RecordingStudioAccessible::AccessInvitation.locate(params[:token])
      head :not_found if @invitation.nil?
    end

    def assign_show_state
      @current_actor = current_actor
      @recording_label = AccessGrantedMailer.recordable_label_for(@invitation.recording)
      @invitation_state = @invitation.state
    end

    def render_sign_in_required
      assign_show_state
      flash.now[:alert] = Copy.t("flashes.sign_in_to_accept")
      render :show, status: :unprocessable_entity
    end

    def redirect_or_render_accept(actor)
      result = RecordingStudioAccessible.accept_access_invitation(
        invitation: @invitation,
        actor: actor,
        controller: self
      )
      return render_accept_failure(result) unless result.success?

      redirect_to access_invitation_path(params[:token]), notice: result.value.notice
    end

    def render_accept_failure(result)
      assign_show_state
      flash.now[:alert] = result.error
      render :show, status: :unprocessable_entity
    end

    def redirect_unsigned_visitor?
      return false if current_actor.present?

      path = local_sign_in_path
      return false if path.blank?

      redirect_to path
      true
    end

    def local_sign_in_path
      url = RecordingStudioAccessible.configuration.access_invitation_sign_in_url_for(
        controller: self,
        token: params[:token],
        email: @invitation.email
      )
      fallback = "/__invitation_sign_in_missing__"
      safe = safe_local_navigation_url(url, fallback: fallback)
      return if safe == fallback

      safe
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end
  end
end
