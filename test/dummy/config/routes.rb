Rails.application.routes.draw do
  devise_for :users
  resources :access_actions, only: [ :show ], param: :action_name
  resources :message_groups, only: [ :index ]
  resources :users, only: [ :show ]
  resources :workspaces, only: [ :show ]
  resource :current_workspace, only: [ :update ]

  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  get "tree", to: "home#tree"
  root "home#index"
end
