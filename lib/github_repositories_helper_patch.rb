require_dependency 'repositories_helper'

module GithubRepositoriesHelperPatch

  def self.included(base)
    base.send(:include, InstanceMethods)
  end

  module InstanceMethods
    def github_field_tags(form, repository)
      content_tag('p', form.text_field(:url, size: 60, required: true,
                                       disabled: !repository.safe_attribute?('url')) +
                       scm_path_info_tag(repository)) +
        content_tag('p', form.password_field(
                      :password, size: 60, name: 'ignore',
                      label: l('redmine_github_adapter.label_api_token'), required: true,
                      value: ((repository.new_record? || repository.password.blank?) ? '' : ('x' * 15)),
                      onfocus: "this.value=''; this.name='repository[password]';",
                      onchange: "this.name='repository[password]';")) +
        content_tag('p', form.check_box(
                      :report_last_commit,
                      label: l(:label_git_report_last_commit)
                    ))
    end
  end
end

RepositoriesHelper.send(:include, GithubRepositoriesHelperPatch)
