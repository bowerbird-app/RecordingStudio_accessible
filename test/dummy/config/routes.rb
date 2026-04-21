Rails.application.routes.draw do
  devise_for :users

  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  root "home#index"
end
