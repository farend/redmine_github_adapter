require File.expand_path('../../test_helper', __FILE__)

class GithubTest < ActiveSupport::TestCase
  plugin_fixtures :repositories, :changesets

  def setup
    @repository = Repository::Github.find(1)
    @changeset = Changeset.find(1)
    @scm = @repository.scm
    @repo = "farend/redmine_github_repo"
  end

  def test_fetch_changesets_Githubでchangesetsが追加される場合
    file = TestFile.new(status: "added", filename: "README.md")
    rev = OctokitRevision.new(identifier: 'shashasha2', scmid: 'shashasha2', author: OctokitAuthor.new(name: 'author_name'), 
                              parents: ['shashasha'], paths: nil, time: Time.gm(2023, 2, 1), message: 'added')
    commit = OctokitCommit.new(sha: 'shashasha2', files: [file], parents: OctokitCommit.new(sha: 'shashasha'))

    @scm.stub(:revisions, build_mock([rev], []) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
      Octokit.stub(:commit, build_mock(commit, []) { |repo, identifier|
        assert_equal @repo, repo
        assert_equal 'shashasha2', identifier
      }) do
        @repository.fetch_changesets
        assert_equal 2, @repository.changesets.size
        assert_equal @repository.id, @repository.changesets.last[:repository_id]

        extra_info = @repository[:extra_info]

        assert_equal '2023-02-01T00:00:00Z', extra_info['last_committed_date']
        assert_equal 'shashasha2', extra_info['last_committed_id']
      end
    end
  end

  def test_fetch_changesets_Githubでchangesetsに追加が無い場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')

    @scm.stub(:revisions, build_mock([rev], []) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
        @repository.fetch_changesets
        assert_equal 1, @repository.changesets.size
        assert_equal @repository.id, @repository.changesets.last[:repository_id]

        extra_info = @repository[:extra_info]

        assert_equal '2023-01-01T00:00:00Z', extra_info['last_committed_date']
        assert_equal 'shashasha', extra_info['last_committed_id']
    end
  end

  def test_save_revisions_Githubでchangesetsが保存される場合
    rev = OctokitRevision.new(identifier: 'shashasha2', scmid: 'shashasha2', author: OctokitAuthor.new(name: 'author_name'), 
                              parents: ['shashasha'], paths: nil, time: Time.gm(2023, 2, 1), message: 'added')
    file = TestFile.new(status: "added", filename: "README.md")
    commit = OctokitCommit.new(sha: 'shashasha2', files: [file], parents: OctokitCommit.new(sha: 'shashasha'))

    @scm.stub(:revisions, build_mock([rev], []) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
      Octokit.stub(:commit, build_mock(commit, []) { |repo, identifier|
        assert_equal @repo, repo
        assert_equal 'shashasha2', identifier
      }) do
        @repository.fetch_changesets
        assert_equal 2, @repository.changesets.size
        assert_equal @repository.id, @repository.changesets.last[:repository_id]

        extra_info = @repository[:extra_info]

        assert_equal '2023-02-01T00:00:00Z', extra_info['last_committed_date']
        assert_equal 'shashasha2', extra_info['last_committed_id']
      end
    end
  end

  def test_fetch_changesets_Githubでchangesetsが保存されない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')

    @scm.stub(:revisions, build_mock([rev], []) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
        @repository.fetch_changesets
        assert_equal 1, @repository.changesets.size
        assert_equal @repository.id, @repository.changesets.last[:repository_id]

        extra_info = @repository[:extra_info]

        assert_equal '2023-01-01T00:00:00Z', extra_info['last_committed_date']
        assert_equal 'shashasha', extra_info['last_committed_id']
    end
  end

  def test_find_changeset_by_name_Githubで引数にリビジョン名が一致するchangesetが存在する場合
    found_changeset = @repository.find_changeset_by_name('shashasha')
    assert_equal @changeset, found_changeset
  end

  def test_find_changeset_by_name_Githubで引数にscmidが部分一致するchangesetが存在する場合
    found_changeset = @repository.find_changeset_by_name('sha')
    assert_equal @changeset, found_changeset
  end

  def test_find_changeset_by_name_Githubで引数に該当するchangesetが存在しない場合
    found_changeset = @repository.find_changeset_by_name('ahsahsahs')
    assert_equal nil, found_changeset
  end

  def test_scm_entries_Githubでキャッシュが存在しない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')
    entry =RepositoryEntry.new(path: "README.md", size: 256, lastrev: rev.identifier)


    @scm.stub(:entries, build_mock([entry], []) { |repository_id, revision|
      assert_equal  'README.md', repository_id
      assert_equal 'shashasha', revision
    }) do
      entries = @repository.scm_entries('README.md', 'shashasha')

      assert_equal 1, entries.size
      assert_equal 'README.md', entries[0].path
      assert_equal 256, entries[0].size
      assert_equal 'shashasha', entries[0].lastrev
      assert_equal 0, GithubAdapterRootFileset.all.size
    end
  end

  def test_scm_entries_Githubでキャッシュが存在する場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')
    entry = RepositoryEntry.new(path: "README.md", size: 256, lastrev: rev.identifier)

    GithubAdapterRootFileset.create!(
      repository_id: @repository.id,
      revision: rev.identifier,
      changeset_id: @changeset.id,
      path: entry.path,
      size: entry.size,
      latest_commitid: rev.identifier
    )

    @scm.stub(:revision_to_sha, build_mock('shashasha', []) { |identifier|
      assert_equal 'shashasha', identifier
    }) do
      @scm.stub(:entries, build_mock([entry], []) { |repository_id, revision|
        assert_equal  'README.md', repository_id
        assert_equal 'shashasha', revision
      }) do
        entries = @repository.scm_entries('README.md', 'shashasha')

        assert_equal 1, entries.size
        assert_equal 'README.md', entries[0].path
        assert_equal 256, entries[0].size
        assert_equal 'shashasha', entries[0].lastrev
        assert_equal 1, GithubAdapterRootFileset.all.size
      end
    end
  end

  def test_latest_changesets_Githubでchangesetが追加されない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')

    @scm.stub(:revisions, build_mock([rev], []) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'shashasha', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('shashasha', [])) do
        latest_changesets = @repository.latest_changesets('README.md', 'shashasha')
        
        assert_equal 1, latest_changesets.size
        assert_equal 'shashasha', latest_changesets.first.revision
        assert_equal 'shashasha', latest_changesets.first.scmid
        assert_equal 'message', latest_changesets.first.comments
        assert_equal Time.gm(2023, 1, 1), latest_changesets.first.committed_on
      end
    end
  end

  def test_latest_changesets_Githubで一件のchangesetが追加される場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')
    latest_rev = OctokitRevision.new(identifier: 'shashalatest', scmid: 'shashalatest', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 2, 1), message: 'latest')
    @repository.changesets << changeset(latest_rev)

    @scm.stub(:revisions, build_mock([rev, latest_rev], []) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'shashalatest', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('shashalatest', [])) do
        latest_changesets = @repository.latest_changesets('README.md', 'shashalatest')
        
        assert_equal 2, latest_changesets.size
        assert_equal 'shashalatest', latest_changesets.first.revision
        assert_equal 'shashalatest', latest_changesets.first.scmid
        assert_equal 'latest', latest_changesets.first.comments
        assert_equal Time.gm(2023, 2, 1), latest_changesets.first.committed_on
      end
    end
  end

  def test_latest_changesets_Githubで対象のpathがデフォルトブランチではない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')
    latest_rev = OctokitRevision.new(identifier: 'shashalatest', scmid: 'shashalatest', author: OctokitAuthor.new(name: 'author_name'), 
                              paths: nil, time: Time.gm(2023, 2, 1), message: 'latest')
    file = TestFile.new(status: "added", filename: "README.md")

    commit = OctokitCommit.new(sha: 'shashalatest', files: [file], parents: OctokitCommit.new(sha: 'shashasha'))

    @scm.stub(:revisions, build_mock([rev, latest_rev], []) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'shashalatest', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('main', [])) do
        Octokit.stub(:commit, build_mock(commit, []) { |repo, identifier|
          assert_equal @repo, repo
          assert_equal 'shashalatest', identifier
        }) do
          latest_changesets = @repository.latest_changesets('README.md', 'shashalatest')
          
          assert_equal 2, latest_changesets.size
          assert_equal 'shashalatest', latest_changesets.first.revision
          assert_equal 'shashalatest', latest_changesets.first.scmid
          assert_equal 'latest', latest_changesets.first.comments
          assert_equal Time.gm(2023, 2, 1), latest_changesets.first.committed_on
        end
      end
    end
  end

  ## 以下、Octokitのモックに使う部品たち ##
  RepositoryChangeset = Struct.new(:repository, :id, :revision, :scmid, :comitter, 
                                   :committed_on, :comments, keyword_init: true)
  RepositoryEntry = Struct.new(:path, :size, :lastrev, keyword_init: true)
  OctokitRevision = Struct.new(:identifier, :scmid, :author, :committer, :tree, 
  :message, :paths, :time, :parents, keyword_init: true)
  OctokitCommit = Struct.new(:sha, :commit, :parents, :files, keyword_init: true)
  OctokitContent = Struct.new(:sha, :name, :path, :type, :size, :download_url, 
  :content, :encoding, keyword_init: true)
  OctokitAuthor = Struct.new(:name, keyword_init: true)
  RootFilesetCache = Struct.new(:repository_id, :revision, :changeset_id, :path, 
                                :size, :latest_comitted, keyword_init: true)
  TestFile = Struct.new(:status, :filename, :previous_filename, 
                        :from_revision, :patch, keyword_init: true)

  def changeset(rev)
    Changeset.new(
      repository: @repository,
      revision: rev.identifier,
      scmid: rev.scmid,
      committer: rev.author,
      committed_on: rev.time,
      comments: rev.message
    )
  end
  
  def build_mock(*returns, &proc)
    mock = Minitest::Mock.new
    Array.wrap(returns).each do |ret|
      mock.expect(:call, ret, &proc)
    end
    mock
  end

end