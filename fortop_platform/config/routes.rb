Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  get "/login", to: "sessions#new", as: :new_session
  post "/auth/github", to: "sessions#create", as: :session
  get "/auth/github/callback", to: "sessions#callback", as: :callback_session
  delete "/logout", to: "sessions#destroy", as: :logout
  get "/setup/github", to: "github/app_setup#new", as: :github_setup
  get "/github/app/manifest/callback", to: "github/app_setup#callback", as: :github_manifest_callback
  post "/github/installations", to: "github/installations#create", as: :github_installation
  get "/github/installations/callback", to: "github/installations#callback", as: :github_installation_callback

  root "repositories#index"
  resources :repositories, only: %i[index new create show destroy] do
    resources :scans, only: %i[create show] do
      post :retry_publication, on: :member
    end
  end
end
