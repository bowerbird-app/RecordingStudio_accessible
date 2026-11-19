# frozen_string_literal: true

module RecordingStudioAccessible
  class AccessRequestsController < ApplicationController
    include AccessRequestsHelper
    include RecordingStudioAccessible::RememberSignupSource

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
      return if redirect_unsigned_visitor?
      return if hold_for_gate?

      render :form
    end

    def create
      return if redirect_unsigned_visitor?
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
    rescue RecordingStudioAccessible::GrantRefused => e
      refuse_access_grant(e, location: review_location)
    end

    def deny
      review(
        RecordingStudioAccessible.deny_access_request(**review_args, review_note: params[:review_note]),
        "requests.flashes.denied"
      )
    end

    def transition
      review(transition_result, "requests.flashes.#{transition_flash}")
    rescue RecordingStudioAccessible::GrantRefused => e
      refuse_access_grant(e, location: review_location)
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

    def redirect_unsigned_visitor?
      return false if current_actor.present?

      path = local_sign_in_path
      if path.blank?
        head :unauthorized
        return true
      end

      store_access_request_return
      remember_signup_source(via: "access_request", recording_id: @recording.id)
      redirect_to path
      true
    end

    def local_sign_in_path
      return nil unless main_app.respond_to?(:new_user_session_path)

      main_app.new_user_session_path
    end

    def store_access_request_return
      return unless respond_to?(:store_location_for, true)

      store_location_for(:user, access_request_return_path)
    end

    def access_request_return_path
      return request.fullpath if request.get?

      new_recording_access_request_path(@recording, **kept_params.compact_blank)
    end

    def requested_role
      params[:role].presence || params.dig(:access_request, :role).presence
    end

    def requested_action
      params[:access_action].presence || params.dig(:access_request, :action).presence
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
      { status: params[:status], role: params[:role], review_note: params[:review_note] }
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
