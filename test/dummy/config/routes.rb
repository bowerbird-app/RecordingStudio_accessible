Rails.application.routes.draw do
  devise_for :users
  resources :users, only: [ :show ]
  resources :workspaces, only: [ :show ]

  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  root "home#index"
end
