module RedmineGithubAdapter
  class Hooks < Redmine::Hook::ViewListener
    render_on :view_repositories_show_contextual, partial: 'annotate_link_patch.js'
  end
end
