# Plugin's routes
# See: http://guides.rubyonrails.org/routing.html

get '/repositories/:id/fetch_from_github', :to => 'github_repositories#fetch'
