Rails.application.routes.draw do
  devise_for :users

  get "/recording_studio", to: redirect("/"), as: nil
  mount RecordingStudio::Engine, at: "/recording_studio"
  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  get "up" => "rails/health#show", as: :rails_health_check

  root "home#index"
end
