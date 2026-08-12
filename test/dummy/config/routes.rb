Rails.application.routes.draw do
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"
  devise_for :users
  resources :access_actions, only: [ :show ], param: :action_name
  resources :message_groups, only: [ :index ]
  resources :users, only: [ :show ]
  resources :workspaces, only: [ :show ]

  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  get "tree", to: "home#tree"
  root "home#index"
end
