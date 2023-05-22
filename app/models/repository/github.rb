require File.expand_path('../../../../lib/redmine/scm/adapters/github_adapter', __FILE__)

class Repository::Github < Repository
  def self.scm_adapter_class
    Redmine::Scm::Adapters::GithubAdapter
  end

  def self.scm_name
    'GitHub'
  end

  def supports_directory_revisions?
    true
  end

  def supports_revision_graph?
    true
  end

  def repo_log_encoding
    'UTF-8'
  end

  def branches
    scm.branches
  end

  def fetch_changesets
    # TODO
  end

  def entries(path, rev)
    # TODO
  end

  def find_changeset_by_name(rev)
  end

  def latest_changesets(path, rev)
  end

  def properties(path, rev)
  end
end
