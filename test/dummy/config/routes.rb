Rails.application.routes.draw do
  mount RecordingStudioRootSwitchable::Engine, at: "/recording_studio_root_switchable"
  mount RecordingStudioInternationalization::Engine, at: "/recording_studio_internationalization"
  devise_for :users
  resources :access_actions, only: [ :show ], param: :action_name
  resources :message_groups, only: [ :index ]
  resources :users, only: [ :show ]
  resources :invitation_signups, param: :token, only: [] do
    member do
      get "new", action: :new, as: :new
      post "create", action: :create, as: :create
    end
  end
  resources :workspaces, only: [ :show, :create ]

  mount RecordingStudioAccessible::Engine, at: "/recording_studio_accessible"

  get "tree", to: "home#tree"
  get "access_request_demo", to: "access_request_demos#show"

  resource :controller_auth_demo, only: [ :show ], controller: "controller_auth_demos" do
    get :authorize
    get :authorize_nil_recording
    get :require_root
  end
  resource :controller_auth_custom_demo, only: [ :show ], controller: "controller_auth_custom_demos" do
    get :authorize
    get :require_root
  end
  resource :controller_auth_override_demo, only: [ :show ], controller: "controller_auth_override_demos"
  resource :controller_auth_site_settings_demo, only: [ :show ], controller: "controller_auth_site_settings_demos"
  resource :controller_auth_stripe_demo, only: [ :show ], controller: "controller_auth_stripe_demos"

  root "home#index"
end
