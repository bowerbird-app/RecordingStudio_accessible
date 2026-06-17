Rails.application.routes.draw do
  devise_for :users
  resources :users, only: [ :show ]
  resources :workspaces, only: [ :show ]

  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  get "tree", to: "home#tree"
  root "home#index"
end
