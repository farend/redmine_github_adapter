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

  def supports_annotate?
    true
  end

  def repo_log_encoding
    'UTF-8'
  end

  # Returns the readable identifier for the given git changeset
  def self.format_changeset_identifier(changeset)
    changeset.revision[0, 8]
  end

  def branches
    scm.branches
  end

  def fetch_changesets(options = {})
    opts = options.merge({
      last_committed_date: extra_info&.send(:[], "last_committed_date"),
      last_committed_id: extra_info&.send(:[], "last_committed_id"),
      all: true
    })

    revisions = scm.revisions('', nil, nil, opts)
    revisions_copy = revisions.clone # revisions will change

    return if revisions.blank?

    save_revisions!(revisions, revisions_copy)

    merge_extra_info({
      last_committed_date: (revisions.last || revisions_copy.last)&.time&.utc&.strftime("%FT%TZ"),
      last_committed_id: (revisions.last || revisions_copy.last)&.scmid
    }.compact.stringify_keys)

    save(validate: false)
  end

  def save_revisions!(revisions, revisions_copy)
    limit = 100
    offset = 0
    while offset < revisions_copy.size
      scmids = revisions_copy.slice(offset, limit).map(&:scmid)
      # Subtract revisions that redmine already knows about
      recent_revisions = changesets.where(scmid: scmids).pluck(:scmid)
      revisions.reject!{|r| recent_revisions.include?(r.scmid)}
      offset += limit
    end

    return if revisions.blank?

    scm.get_filechanges_and_append_to(revisions)

    transaction do
      revisions.each do |rev|
        # There is no search in the db for this revision, because above we ensured,
        # that it's not in the db.
        changeset = Changeset.create!(
          repository:   self,
          revision:     rev.identifier,
          scmid:        rev.scmid,
          committer:    rev.author,
          committed_on: rev.time,
          comments:     rev.message,
        )
        unless changeset.new_record?
          rev.paths.each { |change| changeset.create_change(change) }
        end
      end
      revisions.each do |rev|
        changeset = changesets.find_by(revision: rev.identifier)
        changeset.parents = (rev.parents || []).map{|rp| find_changeset_by_name(rp) }.compact
        changeset.save!
      end
    end
  end
  private :save_revisions!

  def find_changeset_by_name(name)
    if name.present?
      changesets.find_by(revision: name.to_s) ||
        changesets.where('scmid LIKE ?', "#{name}%").first
    end
  end

  def scm_entries(path=nil, identifier=nil)
    is_using_cache = using_root_fileset_cache?(path, identifier)

    if is_using_cache
      sha = scm.revision_to_sha(identifier)
      changeset = find_changeset_by_name(sha)
    end

    # Load from cache
    if changeset.present?
      entries = GithubAdapterRootFileset.where(repository_id: self.id, changeset_id: changeset.id).map { |fileset|
        latest_changeset = find_changeset_by_name(fileset.latest_commitid)
        Redmine::Scm::Adapters::Entry.new(
          name: fileset.path,
          path: fileset.path,
          kind: fileset.size.blank? ? 'dir': 'file',
          size: fileset.size,
          author: latest_changeset.committer,
          lastrev: Redmine::Scm::Adapters::Revision.new(
            identifier: latest_changeset.identifier,
            time: latest_changeset.committed_on
          ),
        )
      }
    end

    # Not found in cache, get entries from SCM
    if entries.blank?
      entries = scm.entries(path, identifier, :report_last_commit => report_last_commit)

      # Save as cache
      if changeset.present?
        GithubAdapterRootFileset.where(repository_id: self.id, revision: identifier).delete_all
        entries.each do |entry|
          GithubAdapterRootFileset.create!(
            repository_id: self.id,
            revision: identifier,
            changeset_id: changeset.id,
            path: entry.path,
            size: entry.size,
            latest_commitid: entry.lastrev.identifier
          )
        end
      end
    end

    entries
  end

  def latest_changesets(path, rev, limit = 10)
    revisions = scm.revisions(path, nil, rev, :limit => limit, :all => false)

    return [] if revisions.nil? || revisions.empty?

    if rev != default_branch
      # Branch that is not default doesn't be synced automatically. so, save it here.
      save_revisions!(revisions, revisions.dup)
    end

    changesets.where(:scmid => revisions.map {|c| c.scmid}).to_a
  end

  def clear_changesets
    super
    GithubAdapterRootFileset.where(repository_id: self.id).delete_all
  end

  def default_branch
    scm.default_branch
  end

  def properties(path, rev)
  end

  def using_root_fileset_cache?(path, identifier)
    return false if path.present?
    return false if identifier.blank?

    example = GithubAdapterRootFileset.where(repository_id: self.id).first
    if example.blank?
      return identifier == default_branch
    end

    if example.revision == identifier
      true
    else
      identifier == default_branch
    end
  end
  private :using_root_fileset_cache?

end
