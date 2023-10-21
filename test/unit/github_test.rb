require File.expand_path('../../test_helper', __FILE__)

class GithubTest < ActiveSupport::TestCase
  plugin_fixtures :repositories, :changesets

  def setup
    @repository = Repository::Github.find(1)
    @default_changeset = Changeset.find(1)
    @scm = @repository.scm
    @repo = "farend/redmine_github_repo"
    @author = OctokitAuthor.new(name: 'author_name')
  end

  def test_fetch_changesets_Githubでchangesetsが追加される場合
    file = TestFile.new(status: "added", filename: "README.md")
    rev = OctokitRevision.new(identifier: 'addedsha', scmid: 'addedsha', author: @author,
                              parents: ['shashasha'], paths: nil, time: Time.gm(2023, 2, 1), message: 'added')

    commit = OctokitCommit.new(sha: 'addedsha', files: [file], parents: OctokitCommit.new(sha: 'shashasha'))

    @scm.stub(:revisions, build_mock([rev]) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
      Octokit.stub(:commit, build_mock(commit) { |repo, identifier|
        assert_equal @repo, repo
        assert_equal 'addedsha', identifier
      }) do
        @repository.fetch_changesets
        assert_equal 2, @repository.changesets.size
        assert_equal @repository.id, @repository.changesets.first[:repository_id]

        extra_info = @repository[:extra_info]

        assert_equal Time.gm(2023, 2, 1), extra_info['last_committed_date']
        assert_equal 'addedsha', extra_info['last_committed_id']
      end
    end
  end

  def test_fetch_changesets_Githubでchangesetsに追加が無い場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')

    @scm.stub(:revisions, build_mock([rev]) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
        @repository.fetch_changesets
        assert_equal 1, @repository.changesets.size
        assert_equal @repository.id, @repository.changesets.first[:repository_id]

        extra_info = @repository[:extra_info]

        assert_equal Time.gm(2023, 1, 1), extra_info['last_committed_date']
        assert_equal 'shashasha', extra_info['last_committed_id']
    end
  end

  def test_save_revisions_Githubでchangesetsが追加される場合
    rev = OctokitRevision.new(identifier: 'addedsha', scmid: 'addedsha', author: @author,
                              parents: ['shashasha'], paths: nil, time: Time.gm(2023, 2, 1), message: 'added')
    file = TestFile.new(status: "added", filename: "README.md")
    commit = OctokitCommit.new(sha: 'addedsha', files: [file], parents: OctokitCommit.new(sha: 'shashasha'))

    Octokit.stub(:commit, build_mock(commit) { |repo, identifier|
      assert_equal @repo, repo
      assert_equal 'addedsha', identifier
    }) do
      @repository.send(:save_revisions!, [rev], [rev])

      assert_equal 2, @repository.changesets.size
      assert_equal @repository.id, @repository.changesets.first[:repository_id]
      assert_equal rev.identifier, @repository.changesets.first[:revision]
      assert_equal rev.scmid, @repository.changesets.first[:scmid]
      assert_equal rev.author.name, @repository.changesets.first[:committer]
      assert_equal rev.time, @repository.changesets.first[:committed_on]
      assert_equal rev.message, @repository.changesets.first[:comments]

      assert_equal file.filename, @repository.changesets.first.filechanges.first.path
      assert_equal "A", @repository.changesets.first.filechanges.first.action
      assert_nil   @repository.changesets.first.filechanges.first.from_path

      assert_equal 1, @repository.changesets.first.parents.length
      assert_equal @default_changeset, @repository.changesets.first.parents.first
    end
  end

  def test_save_revisions_Githubでchangesetsが追加されない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                              paths: nil, time: Time.gm(2023, 1, 1), message: 'message')

    @repository.send(:save_revisions!, [rev], [rev])

    assert_equal 1, @repository.changesets.size
    assert_equal @default_changeset.id, @repository.changesets.first.id
  end

  def test_find_changeset_by_name_Githubで引数にリビジョン名が一致するchangesetが存在する場合
    found_changeset = @repository.find_changeset_by_name('shashasha')
    assert_equal @default_changeset, found_changeset
  end

  def test_find_changeset_by_name_Githubで引数にscmidが部分一致するchangesetが存在する場合
    found_changeset = @repository.find_changeset_by_name('sha')
    assert_equal @default_changeset, found_changeset
  end

  def test_find_changeset_by_name_Githubで引数に該当するchangesetが存在しない場合
    found_changeset = @repository.find_changeset_by_name('ahsahsahs')
    assert_nil found_changeset
  end

  def test_scm_entries_Githubでルートファイルのキャッシュが存在しないし使われない場合
    rev = OctokitRevision.new(identifier: 'mock-value', scmid: 'mock-value', author: @author,
                              time: Time.gm(2023, 1, 1), message: 'message')
    entry = RepositoryEntry.new(path: "README.md", size: 256, lastrev: rev.identifier)

    @scm.stub(:entries, build_mock([entry]) { |repository_id, revision|
      assert_equal  'README.md', repository_id
      assert_equal 'shashasha', revision
    }) do
      entries = @repository.scm_entries('README.md', 'shashasha')

      assert_equal 1, entries.size
      assert_equal 'README.md', entries[0].path
      assert_equal 256, entries[0].size
      assert_equal 'mock-value', entries[0].lastrev

      assert_equal 0, GithubAdapterRootFileset.all.size
    end
  end

  def test_scm_entries_Githubでルートファイルのキャッシュは存在するが使用しない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                              time: Time.gm(2023, 1, 1), message: 'message')
    entry = RepositoryEntry.new(path: "README.md", size: 256, lastrev: rev.identifier)

    GithubAdapterRootFileset.create!(
      repository_id: @repository.id,
      revision: rev.identifier,
      changeset_id: @default_changeset.id,
      path: entry.path,
      size: entry.size,
      latest_commitid: rev.identifier
    )

    @scm.stub(:entries, build_mock([entry]) { |repository_id, revision|
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

  def test_scm_entries_Githubでルートファイルのキャッシュが存在し使用する場合
    main_changeset = Changeset.create!(
      repository_id: @repository.id,
      revision: "sha1-abc",
      committer: 'author_name',
      committed_on: '2023-01-01',
      comments: 'message',
      commit_date: '2023-01-01',
      scmid: 'sha1-abc'
    )
    GithubAdapterRootFileset.create!(
      repository_id: @repository.id,
      revision: "sha1-abc",
      changeset_id: main_changeset.id,
      path: "README.md",
      size: 256,
      latest_commitid: "shashasha"
    )

    @scm.stub(:default_branch, build_mock('main')) do
      @scm.stub(:revision_to_sha, build_mock('sha1-abc') { |identifier|
        assert_equal 'main', identifier
      }) do
        entries = @repository.scm_entries('', 'main')

        assert_equal 1, entries.size
        assert_equal 'README.md', entries[0].name
        assert_equal 'README.md', entries[0].path
        assert_equal 'file', entries[0].kind
        assert_equal 256, entries[0].size
        assert_equal 'author_name', entries[0].author
        assert_equal 'shashasha', entries[0].lastrev.identifier
        assert_equal Time.parse("2023-01-01 00:00:00"), entries[0].lastrev.time

        assert_equal 1, GithubAdapterRootFileset.all.size
      end
    end
  end

  def test_scm_entries_Githubでルートファイルのキャッシュは存在しないが使用する場合
    main_changeset = Changeset.create!(
      repository_id: @repository.id,
      revision: "sha1-abc",
      committer: 'author_name',
      committed_on: '2023-01-01',
      comments: 'message',
      commit_date: '2023-01-01',
      scmid: 'sha1-abc'
    )
    # scm.entries の戻り値
    entry = RepositoryEntry.new(path: "README.md", size: 256, lastrev: OctokitRevision.new(
      identifier: 'shashasha', scmid: 'shashasha', author: @author, time: Time.gm(2023, 1, 1), message: 'message'
      )
    )

    @scm.stub(:default_branch, build_mock('main')) do
      @scm.stub(:revision_to_sha, build_mock('sha1-abc') { |identifier|
        assert_equal 'main', identifier
      }) do
        @scm.stub(:entries, build_mock([entry]) { |path, identifier|
          assert_equal '', path
          assert_equal 'main', identifier
        }) do
          entries = @repository.scm_entries('', 'main')

          assert_equal 1, entries.size
          assert_equal 'README.md', entries[0].path
          assert_equal 256, entries[0].size
          assert_equal 'shashasha', entries[0].lastrev.identifier
          assert_equal Time.gm(2023, 1, 1), entries[0].lastrev.time

          # 作成された RootFileset の確認
          assert_equal 1, GithubAdapterRootFileset.all.size
          assert_equal @repository.id, GithubAdapterRootFileset.first.repository_id
          assert_equal 'main', GithubAdapterRootFileset.first.revision
          assert_equal main_changeset.id, GithubAdapterRootFileset.first.changeset_id
          assert_equal entry.path, GithubAdapterRootFileset.first.path
          assert_equal entry.size.to_s, GithubAdapterRootFileset.first.size
          assert_equal entry.lastrev.identifier, GithubAdapterRootFileset.first.latest_commitid
        end
      end
    end
  end

  def test_latest_changesets_Githubでidentifierにデフォルトブランチ名が与えられ未反映のrevisionが存在しない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                              time: Time.parse("2023-01-01 00:00:00"), message: 'message')

    @scm.stub(:revisions, build_mock([rev]) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'main', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('main')) do
        assert_no_difference 'Changeset.count' do

          latest_changesets = @repository.latest_changesets('README.md', 'main')

          assert_equal 1, latest_changesets.size
          assert_equal 'shashasha', latest_changesets.first.revision
          assert_equal 'shashasha', latest_changesets.first.scmid
          assert_equal 'message', latest_changesets.first.comments
          assert_equal Time.parse("2023-01-01 00:00:00"), latest_changesets.first.committed_on
        end
      end
    end
  end

  def test_latest_changesets_Githubでidentifierにデフォルトブランチ名が与えられ未反映のrevisionが存在した場合
    rev1 = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                               time: Time.gm(2023, 1, 1), message: 'message')
    rev2 = OctokitRevision.new(identifier: 'latestsha', scmid: 'latestsha', author: @author,
                               time: Time.gm(2023, 1, 1), message: 'latest')
    cgs2 = Changeset.create!(
      repository_id: @repository.id,
      revision: "latestsha",
      committer: 'author_name',
      committed_on: Time.parse('2023-01-02'),
      comments: 'latest message',
      commit_date: '2023-01-02',
      scmid: 'latestsha'
    )

    @scm.stub(:revisions, build_mock([rev1, rev2]) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'main', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('main')) do
        assert_no_difference 'Changeset.count' do

          latest_changesets = @repository.latest_changesets('README.md', 'main')

          assert_equal 2, latest_changesets.size
          assert_equal 'latestsha', latest_changesets.first.revision
          assert_equal 'latestsha', latest_changesets.first.scmid
          assert_equal 'latest message', latest_changesets.first.comments
          assert_equal Time.parse("2023-01-02"), latest_changesets.first.committed_on

          assert_equal 'shashasha', latest_changesets.last.revision
          assert_equal 'shashasha', latest_changesets.last.scmid
          assert_equal 'message', latest_changesets.last.comments
          assert_equal Time.parse("2023-01-01"), latest_changesets.last.committed_on
        end
      end
    end
  end

  def test_latest_changesets_GithubでidentifierにデフォルトブランチでないSHA1ハッシュが与えられ未反映のrevisionが存在する場合
    rev1 = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                               time: Time.gm(2023, 1, 1), message: 'message')
    rev2 = OctokitRevision.new(identifier: 'latestsha', scmid: 'latestsha', author: @author,
                               time: Time.gm(2023, 2, 1), message: 'latest')
    commit = OctokitCommit.new(sha: 'latestsha', files: [TestFile.new(status: "added", filename: "README.md")],
                               parents: OctokitCommit.new(sha: 'shashasha'))

    @scm.stub(:revisions, build_mock([rev1, rev2]) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'latestsha', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('main')) do
        Octokit.stub(:commit, build_mock(commit) { |repo, identifier|
          assert_equal @repo, repo
          assert_equal 'latestsha', identifier
        }) do
          assert_difference 'Changeset.count', 1 do

            latest_changesets = @repository.latest_changesets('README.md', 'latestsha')

            assert_equal 2, latest_changesets.size
            assert_equal 'latestsha', latest_changesets.first.revision
            assert_equal 'latestsha', latest_changesets.first.scmid
            assert_equal 'latest', latest_changesets.first.comments
            assert_equal Time.gm(2023, 2, 1), latest_changesets.first.committed_on

            assert_equal 'shashasha', latest_changesets.last.revision
            assert_equal 'shashasha', latest_changesets.last.scmid
            assert_equal 'message', latest_changesets.last.comments
            assert_equal Time.parse("2023-01-01"), latest_changesets.last.committed_on
          end
        end
      end
    end
  end

  def test_latest_changesets_GithubでidentifierにデフォルトブランチでないSHA1ハッシュが与えられ未反映のrevisionが存在しない場合
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: @author,
                              time: Time.parse("2023-01-01 00:00:00"), message: 'message')

    @scm.stub(:revisions, build_mock([rev]) { |path, identifier_from, identifier_to|
      assert_equal 'README.md', path
      assert_equal nil, identifier_from
      assert_equal 'shashasha', identifier_to
    }) do
      @repository.stub(:default_branch, build_mock('main')) do
        assert_no_difference 'Changeset.count' do

          latest_changesets = @repository.latest_changesets('README.md', 'shashasha')

          assert_equal 1, latest_changesets.size
          assert_equal 'shashasha', latest_changesets.first.revision
          assert_equal 'shashasha', latest_changesets.first.scmid
          assert_equal 'message', latest_changesets.first.comments
          assert_equal Time.parse("2023-01-01 00:00:00"), latest_changesets.first.committed_on
        end
      end
    end
  end

  def test_using_root_fileset_cache_Githubでpathが指定されている場合
    is_using_cache = @repository.send(:using_root_fileset_cache?, 'README.md', 'main')

    assert !is_using_cache
  end

  def test_using_root_fileset_cache_Githubでキャッシュが存在せずidentifierにデフォルトブランチ名以外を指定した場合
    @scm.stub(:default_branch, build_mock('main')) do
      is_using_cache = @repository.send(:using_root_fileset_cache?, '', 'feature_branch')

      assert !is_using_cache
    end
  end

  def test_using_root_fileset_cache_Githubでキャッシュが存在せずidentifierにデフォルトブランチ名を指定した場合
    @scm.stub(:default_branch, build_mock('main')) do
      is_using_cache = @repository.send(:using_root_fileset_cache?, '', 'main')

      assert is_using_cache
    end
  end

  def test_using_root_fileset_cache_Githubでキャッシュが存在しidentifierとしてキャッシュのrevisionが指定された場合
    GithubAdapterRootFileset.create!(
      repository_id: @repository.id,
      revision: 'shashasha',
      changeset_id: @default_changeset.id,
      path: "README.md",
      size: 256,
      latest_commitid: 'shashasha'
    )

    @scm.stub(:default_branch, build_mock('main')) do
      is_using_cache = @repository.send(:using_root_fileset_cache?, '', 'shashasha')

      assert is_using_cache
    end
  end

  def test_using_root_fileset_cache_Githubでキャッシュが存在しidentifierにデフォルトブランチ名を受け取った場合
    GithubAdapterRootFileset.create!(
      repository_id: @repository.id,
      revision: 'shashasha',
      changeset_id: @default_changeset.id,
      path: "README.md",
      size: 256,
      latest_commitid: 'shashasha'
    )

    @scm.stub(:default_branch, build_mock('main')) do
      is_using_cache = @repository.send(:using_root_fileset_cache?, '', 'main')

      assert is_using_cache
    end
  end

  def test_using_root_fileset_cache_Githubでキャッシュが存在しidentifierに別のコミットIDが指定されている場合
    GithubAdapterRootFileset.create!(
      repository_id: @repository.id,
      revision: 'shashasha',
      changeset_id: @default_changeset.id,
      path: "README.md",
      size: 256,
      latest_commitid: 'shashasha'
    )

    @scm.stub(:default_branch, build_mock('main')) do
      is_using_cache = @repository.send(:using_root_fileset_cache?, '', 'othershasha')

      assert !is_using_cache
    end
  end

  ## 以下、Octokitのモックに使う部品たち ##
  OctokitRevision = Struct.new(:identifier, :scmid, :author, :committer, :tree,
                               :message, :paths, :time, :parents, keyword_init: true)
  OctokitCommit = Struct.new(:sha, :commit, :parents, :files, keyword_init: true)
  OctokitContent = Struct.new(:sha, :name, :path, :type, :size, :download_url,
                              :content, :encoding, keyword_init: true)
  OctokitAuthor = Struct.new(:name, keyword_init: true)
  RepositoryChangeset = Struct.new(:repository, :id, :revision, :scmid, :comitter,
                                   :committed_on, :comments, keyword_init: true)
  RepositoryEntry = Struct.new(:path, :size, :lastrev, keyword_init: true)
  TestFile = Struct.new(:status, :filename, :previous_filename,
                        :from_revision, :patch, keyword_init: true)
  # メソッドの定義
  OctokitAuthor.define_method(:to_s) { self.name }

  def build_mock(*returns, &proc)
    mock = Minitest::Mock.new
    Array.wrap(returns).each do |ret|
      mock.expect(:call, ret, &proc)
    end
    mock
  end

end
