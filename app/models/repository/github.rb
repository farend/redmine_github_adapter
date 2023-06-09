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
    scm_brs = branches
    return if scm_brs.blank?

    save_revisions(nil, nil, nil)
  end

  def find_changeset_by_name(name)
    if name.present?
      changesets.find_by(revision: name.to_s) ||
        changesets.where('scmid LIKE ?', "#{name}%").first
    end
  end

  def save_revisions(prev_db_heads, repo_heads, last_committed_date)
    h = {}
    opts = {}
    opts[:last_committed_date] = last_committed_date
    opts[:all] = true

    revisions = scm.revisions('', nil, nil, opts)
    return if revisions.blank?

    limit = 100
    offset = 0
    revisions_copy = revisions.clone # revisions will change
    while offset < revisions_copy.size
      scmids = revisions_copy.slice(offset, limit).map{|x| x.scmid}
      recent_changesets_slice = changesets.where(:scmid => scmids)
      # Subtract revisions that redmine already knows about
      recent_revisions = recent_changesets_slice.map{|c| c.scmid}
      revisions.reject!{|r| recent_revisions.include?(r.scmid)}
      offset += limit
    end
    revisions.each do |rev|
      transaction do
        # There is no search in the db for this revision, because above we ensured,
        # that it's not in the db.
        save_revision(rev)
      end
    end

    if revisions_copy.size > 0
      h["last_committed_date"] = revisions_copy.last.time.utc.strftime("%FT%TZ")
    end

    if revisions.size > 0
      h["last_committed_date"] = revisions.last.time.utc.strftime("%FT%TZ")
    end

    merge_extra_info(h)
    save(:validate => false)
  end
  private :save_revisions

  def save_revision(rev)
    parents = (rev.parents || []).map{|rp| find_changeset_by_name(rp)}.compact
    changeset = Changeset.create(
              :repository   => self,
              :revision     => rev.identifier,
              :scmid        => rev.scmid,
              :committer    => rev.author,
              :committed_on => rev.time,
              :comments     => rev.message,
              :parents      => parents
              )
    unless changeset.new_record?
      rev.paths.each { |change| changeset.create_change(change) }
    end
    changeset
  end
  private :save_revision

  def scm_entries(path=nil, identifier=nil)
    scm.entries(path, identifier, :report_last_commit => report_last_commit)
  end

  def latest_changesets(path, rev, limit = 10)
    revisions = scm.revisions(path, nil, rev, :limit => limit, :all => false)

    return [] if revisions.nil? || revisions.empty?
    changesets.where(:scmid => revisions.map {|c| c.scmid}).to_a
  end

  def relative_path(path)
    get_path_name(path)
  end

  def default_branch
    scm.default_branch
  end

  def properties(path, rev)
  end
end
