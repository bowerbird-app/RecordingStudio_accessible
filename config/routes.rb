# frozen_string_literal: true

RecordingStudioAccessible::Engine.routes.draw do
  root "home#index"
  get :overview, to: "home#overview"
  get :methods, to: "home#access_methods"
  get :user_invites, to: "home#user_invites"
  get :email_template, to: "home#email_template"

  resources :recordings, only: [] do
    resources :accesses, only: %i[index new create edit update destroy], controller: "recording_accesses"
  end
end
