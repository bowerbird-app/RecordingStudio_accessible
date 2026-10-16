# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestsController < ApplicationController
    include AccessRequestsHelper
    include AccessRequestSignIn

    helper AccessRequestsHelper
    helper_method :manager?

    skip_before_action :authenticate_user!, raise: false
    before_action :set_recording
    before_action :require_request_parent!
    layout :access_request_layout

    def index
      return head :forbidden unless manager?

      @requests = AccessRequestQuery.for_parent(@recording)
    end

    def show
      @request_recording = find_request
      return head :not_found unless AccessRequestQuery.visible?(
        request_recording: @request_recording, actor: current_actor, controller: self
      )

      @events = request_events(@request_recording)
    end

    def new
      render current_actor ? :form : :email
    end

    def submit_email
      AccessRequestIntake.start!(**intake_args)
      redirect_to verify_recording_access_requests_path(@recording, **presentation_params)
    rescue AccessRequestIntake::Error => e
      flash.now[:alert] = e.message
      render :email, status: :unprocessable_entity
    end

    def verify
      @intent = open_intent
      head :not_found unless @intent
    end

    def submit_verification
      @intent = open_intent
      return head :not_found unless @intent

      sign_in_verified_requester(AccessRequestIntake.verify!(intent: @intent, code: params[:code], session: session))
      redirect_to form_after_verification
    rescue AccessRequestIntake::Error => e
      flash.now[:alert] = e.message
      render :verify, status: :unprocessable_entity
    end

    def resend
      @intent = open_intent
      return head :not_found unless @intent

      AccessRequestIntake.resend!(intent: @intent, request: request, session: session)
      redirect_to verify_recording_access_requests_path(@recording, **presentation_params),
                  notice: Copy.t("requests.flashes.code_resent")
    rescue AccessRequestIntake::Error => e
      flash.now[:alert] = e.message
      render :verify, status: :unprocessable_entity
    end

    def create
      return redirect_to new_recording_access_request_path(@recording, **kept_params) unless current_actor

      result = submit_request
      result.success? ? redirect_after_submit(result) : render_request_error(result)
    end

    def sent
      @request_recording = sent_request
    end

    def approve
      review(RecordingStudioAccessible.approve_access_request(**review_args), "requests.flashes.approved")
    end

    def deny
      review(
        RecordingStudioAccessible.deny_access_request(**review_args, review_note: params[:review_note]),
        "requests.flashes.denied"
      )
    end

    def withdraw
      result = RecordingStudioAccessible.withdraw_access_request(
        request_recording: find_request, actor: current_actor, controller: self
      )
      redirect_to sent_recording_access_requests_path(@recording, **presentation_params),
                  (result.success? ? { notice: Copy.t("requests.flashes.withdrawn") } : { alert: result.error })
    end

    private

    def access_request_layout
      return false if modal_frame_request?
      return "recording_studio_accessible/blank" if %w[index show].include?(action_name)

      "recording_studio_accessible/access_request"
    end

    def set_recording
      @recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    end

    def require_request_parent!
      head :not_found unless Compatibility.access_request_parent_allowed?(@recording)
    end

    def manager?
      AccessManagementPolicy.allowed?(recording: @recording, actor: current_actor, controller: self)
    end

    def current_actor
      RecordingStudioAccessible.configuration.current_actor_for(controller: self)
    end

    def intake_args
      {
        recording: @recording, email: params[:email], name: params[:name], role: requested_role,
        action: requested_action, request: request, session: session
      }
    end

    def requested_role
      params[:role].presence || params.dig(:access_request, :role).presence
    end

    def requested_action
      params[:access_action].presence || params.dig(:access_request, :action).presence
    end

    def open_intent
      intent = AccessRequestIntent.find_by(id: session[AccessRequestIntake::SESSION_KEY])
      intent if intent && intent.recording_id == @recording.id
    end

    def form_after_verification
      new_recording_access_request_path(
        @recording, role: @intent.role, access_action: @intent.action, **presentation_params
      )
    end

    def submit_request
      RecordingStudioAccessible.request_access(
        recording: @recording, actor: current_actor, role: requested_role,
        action: requested_action, message: params.dig(:access_request, :message), controller: self
      )
    end

    def redirect_after_submit(result)
      session[:recording_studio_accessible_access_request_id] = result.value&.id
      notice = result.value ? Copy.t("requests.flashes.submitted") : Copy.t("requests.already")
      redirect_to sent_recording_access_requests_path(@recording, **presentation_params), notice: notice
    end

    def render_request_error(result)
      flash.now[:alert] = result.error
      render :form, status: :unprocessable_entity
    end

    def sent_request
      recording_id = session[:recording_studio_accessible_access_request_id]
      recording = RecordingStudio::Recording.unscoped.find_by(id: recording_id)
      recording if recording&.parent_recording_id == @recording.id
    end

    def find_request
      RecordingStudio::Recording.unscoped.find(params[:id])
    end

    def review(result, notice_key)
      options = result.success? ? { notice: Copy.t(notice_key) } : { alert: result.error }
      redirect_to recording_access_request_path(@recording, find_request), options
    end

    def review_args
      { request_recording: find_request, manager_actor: current_actor, controller: self }
    end

    def request_events(recording)
      return [] unless recording.respond_to?(:events)

      recording.events.where(action: RecordingStudio::AccessRequest::EVENTS).reorder(occurred_at: :asc, id: :asc)
    end

    def presentation_params
      modal_presentation? ? { presentation: AccessRequestsHelper::MODAL } : {}
    end

    def kept_params
      presentation_params.merge(role: requested_role, access_action: requested_action)
    end
  end
end
