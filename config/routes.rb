ActionController::Routing::Routes.draw do |map|
  map.resources :comments

  map.resources :episodes

  map.resources :podcasts, :collection => { :feed_info => :any }

  map.resources :users
  map.activate  '/activate/:activation_code', :controller => "users", :action => "activate"
  map.signup    '/signup', :controller => "users", :action => "new"
  map.login     '/login', :controller => "sessions", :action => "new"
  map.logout    '/logout', :controller => "sessions", :action => "destroy"

  map.resource :session

  # You can have the root of your site routed with map.root -- just remember to delete public/index.html.
  map.root :controller => "home", :action => "home"
end
