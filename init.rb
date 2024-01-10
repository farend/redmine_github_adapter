require 'redmine'
require File.expand_path('../lib/github_repositories_helper_patch', __FILE__)
require File.expand_path('../lib/redmine_github_adapter/hooks', __FILE__)

Redmine::Plugin.register :redmine_github_adapter do
  name 'Redmine Github Adapter plugin'
  author 'Author name'
  description 'This is a plugin for Redmine'
  version '0.0.2'
  url 'http://example.com/path/to/plugin'
  author_url 'http://example.com/about'
  Redmine::Scm::Base.add "Github"
end
