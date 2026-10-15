Rails.application.routes.draw do
  get "api/health", to: "api/v1/health#show"

  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      resources :employees, only: %i[index show]
      resources :liquidaciones, only: %i[index show] do
        collection do
          post :calculate
        end
      end
    end
  end
end
