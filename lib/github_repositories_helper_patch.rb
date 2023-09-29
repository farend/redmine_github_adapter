require_dependency 'repositories_helper'

module GithubRepositoriesHelperPatch

  def self.included(base)
    base.send(:include, InstanceMethods)
  end

  module InstanceMethods
    def github_field_tags(form, repository)
      field_tags = []
      field_tags << content_tag(
        'p',
        form.text_field(:url, size: 60, required: true, disabled: !repository.safe_attribute?('url')) +
        scm_path_info_tag(repository)
      )
      field_tags << content_tag(
        'p',
        form.password_field(
          :password, size: 60, name: 'ignore',
          label: l('redmine_github_adapter.label_api_token'), required: true,
          value: ((repository.new_record? || repository.password.blank?) ? '' : ('x' * 15)),
          onfocus: "this.value=''; this.name='repository[password]';",
          onchange: "this.name='repository[password]';"
        )
      )
      field_tags << content_tag(
        'p',
        form.check_box(
          :report_last_commit,
          label: l(:label_git_report_last_commit)
        )
      )
      if repository&.persisted?
        field_tags << content_tag(
          'p',
          button_tag(data: { fetchfrom: 'github' }) { l('redmine_github_adapter.label_sync_button') }
        )
        field_tags << content_tag(
          'script', github_fetch_js(repository).html_safe
        )
      end
      field_tags.join.html_safe
    end

    def github_fetch_js(repository)
      <<EOS
$(function(){
  function fetchFromGithub() {
    return $.ajax("/repositories/#{repository.id}/fetch_from_github")
    .then(function(data, textStatus, jqXHR){
      if (data.status == 'OK') return;
      if (data.status == 'Processing') return fetchFromGithub();
      throw "Unexpected Status: " + JSON.stringify(data);
    });
  }

  $('button[data-fetchfrom=github]').on('click', function(e){
    e.preventDefault()
    $(this).prop('disabled', true);
    fetchFromGithub()
    .then(() => {
      $(this).prop('disabled', false);
    })
    return false;
  });
});
EOS
    end
  end
end

RepositoriesHelper.send(:include, GithubRepositoriesHelperPatch)
