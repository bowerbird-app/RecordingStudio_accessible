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
    before_action :remember_access_request_copy
    recording_studio_layout { modal_frame_request? ? false : RecordingStudioAccessible.configuration.layout }

    def index
      return head :forbidden unless manager?

      @list_url = recording_access_requests_path(@recording)
      @page = access_request_index_page
    end

    def show
      @request_recording = find_request
      head :not_found unless AccessRequestQuery.visible?(
        request_recording: @request_recording, actor: current_actor, controller: self
      )
    end

    def new
      return render(:email) unless current_actor
      return if hold_for_gate?

      render :form
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
      redirect_after_verification
    rescue AccessRequestIntake::Error => e
      flash.now[:alert] = e.message
      render :verify, status: :unprocessable_entity
    end

    def resend
      @intent = open_intent
      return head :not_found unless @intent

      AccessRequestIntake.resend!(intent: @intent, request: request, session: session)
      redirect_to verify_recording_access_requests_path(@recording, **presentation_params),
                  notice: access_request_t("flashes.code_resent")
    rescue AccessRequestIntake::Error => e
      flash.now[:alert] = e.message
      render :verify, status: :unprocessable_entity
    end

    def create
      return redirect_to new_recording_access_request_path(@recording, **kept_params) unless current_actor
      return if hold_for_gate?

      result = submit_request
      result.success? ? redirect_after_submit(result) : render_request_error(result)
    end

    def sent
      @request_recording = sent_request
    end

    def approve
      review(
        RecordingStudioAccessible.approve_access_request(**review_args, role: params[:role]),
        "requests.flashes.approved"
      )
    end

    def deny
      review(
        RecordingStudioAccessible.deny_access_request(**review_args, review_note: params[:review_note]),
        "requests.flashes.denied"
      )
    end

    def transition
      review(transition_result, "requests.flashes.#{transition_flash}")
    end

    private

    def access_request_index_page
      AccessRequestIndex.page(
        recordings: @recording, actor: current_actor, controller: self,
        status: params[:status], cursor: params[:cursor]
      )
    end

    def set_recording
      @recording = RecordingStudio::Recording.unscoped.find(params[:recording_id])
    end

    def remember_access_request_copy
      AccessRequestCopy.remember(session, @recording.id, params)
    end

    def require_request_parent!
      head :not_found unless Compatibility.access_request_parent_allowed?(@recording)
    end

    def manager?
      AccessManagementPolicy.allowed?(recording: access_request_parent, actor: current_actor, controller: self)
    end

    def access_request_parent
      @request_recording&.parent_recording || @recording
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

    def redirect_after_verification
      return if hold_for_gate?(role: @intent.role, action: @intent.action)

      redirect_to form_after_verification
    end

    def hold_for_gate?(role: requested_role, action: requested_action)
      gate_held?(gate_decision(role, action))
    end

    def gate_decision(role, action)
      AccessRequestGate.decide(
        recording: @recording, actor: current_actor, action: action,
        request: request, carry: carry_params(role, action)
      )
    end

    def carry_params(role, action)
      presentation_params.merge(role: role.presence, access_action: action.presence).compact
    end

    def gate_held?(decision)
      return false if decision[:status] == :open

      if decision[:status] == :redirect
        redirect_to(decision[:location])
      else
        flash.now[:alert] = access_request_t("errors.gate_unavailable")
        render :gate_closed, status: :unprocessable_entity
      end
      true
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
      notice = result.value ? access_request_t("flashes.submitted") : access_request_t("already")
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
      RecordingStudio::Recording.unscoped.where(parent_recording_id: @recording.id).find(params[:id])
    end

    def review(result, notice_key)
      options = result.success? ? { notice: Copy.t(notice_key) } : { alert: result.error }
      redirect_to review_location, options
    end

    def review_location
      return list_review_location if params[:return_to].to_s == "list"

      recording_access_request_path(@recording, find_request, **presentation_params)
    end

    def list_review_location
      args = { status: list_status_param }.compact
      return access_requests_path(**args) if params[:list_scope].to_s == "collection"

      recording_access_requests_path(@recording, **args)
    end

    def list_status_param
      status = params[:list_status].to_s
      return unless AccessRequestIndex::STATUSES.include?(status)
      return if status == AccessRequestIndex::DEFAULT_STATUS

      status
    end

    def review_args
      { request_recording: find_request, manager_actor: current_actor, controller: self }
    end

    def transition_result
      RecordingStudioAccessible.transition_access_request(**review_args, **transition_params)
    end

    def transition_params
      { status: params[:status], role: submitted_role, review_note: params[:review_note] }
    end

    def submitted_role
      params[:role].presence || params["role_#{find_request.id}"].presence
    end

    def transition_flash
      AccessRequestTransitions.flash_key(params[:status]) || "approved"
    end

    def presentation_params
      modal_presentation? ? { presentation: AccessRequestsHelper::MODAL } : {}
    end

    def kept_params
      presentation_params.merge(role: requested_role, access_action: requested_action)
    end
  end
end
