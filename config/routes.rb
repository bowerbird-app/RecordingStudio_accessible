# frozen_string_literal: true

RecordingStudioAccessible::Engine.routes.draw do
  root "home#index"
  get :overview, to: "home#overview"
  get :methods, to: "home#access_methods"
  get :user_invites, to: "home#user_invites"
  get :email_template, to: "home#email_template"
  get "workspaces/:workspace_id/actor_access_points", to: "actor_access_points#index",
                                                      as: :workspace_actor_access_points

  resources :recordings, only: [] do
    resources :accesses, only: %i[index new create edit update destroy], controller: "recording_accesses"
    resources :access_invitations, only: [:destroy], controller: "recording_access_invitations" do
      member { post :resend }
    end
  end

  get "access_invitations/:token", to: "access_invitations#show", as: :access_invitation,
                                   constraints: { token: /[A-Za-z0-9_-]{20,}/ }
  post "access_invitations/:token/accept", to: "access_invitations#accept", as: :accept_access_invitation,
                                           constraints: { token: /[A-Za-z0-9_-]{20,}/ }
end
