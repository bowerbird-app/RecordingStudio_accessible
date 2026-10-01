# frozen_string_literal: true

class InvitationSignupsController < ApplicationController
  skip_before_action :authenticate_user!

  before_action :set_invitation

  def new
    @existing_user = User.find_by(email: @invitation.email)
  end

  def create
    if User.exists?(email: @invitation.email)
      @existing_user = User.find_by(email: @invitation.email)
      flash.now[:alert] = "An account for #{@invitation.email} already exists. Sign in to accept this invitation."
      render :new, status: :unprocessable_entity
      return
    end

    password = signup_password
    user = User.new(email: @invitation.email, password: password, password_confirmation: password)
    unless user.save
      flash.now[:alert] = user.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
      return
    end

    sign_in(user)
    result = RecordingStudioAccessible.accept_access_invitation(invitation: @invitation, actor: user)
    if result.success?
      redirect_to root_path, notice: "Access granted."
    else
      flash.now[:alert] = result.error
      render :new, status: :unprocessable_entity
    end
  end

  private

  def set_invitation
    @invitation = RecordingStudioAccessible::AccessInvitation.locate(params[:token])
    head :not_found if @invitation.nil?
  end

  def signup_password
    params.fetch(:invitation_signup, ActionController::Parameters.new).permit(:password)[:password].to_s
  end
end
