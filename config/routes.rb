Rails.application.routes.draw do
  # Redirect to localhost from 127.0.0.1 to use same IP address with Vite server
  constraints(host: "127.0.0.1") do
    get "(*path)", to: redirect { |params, req| "#{req.protocol}localhost:#{req.port}/#{params[:path]}" }
  end
  devise_for :users
  root "dashboard#index"

  resources :topics, only: [ :index ] do
    resource :subscription, only: [ :create, :update, :destroy ],
                            controller: "topic_subscriptions"
  end

  namespace :admin do
    root "topics#index"
    resources :topics, except: [ :destroy, :show ]
  end

  post "matches/:id/mark_posted", to: "matches#mark_posted", as: :mark_posted_match
  post "matches/:id/dismiss", to: "matches#dismiss", as: :dismiss_match
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
