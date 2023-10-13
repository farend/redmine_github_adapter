require File.expand_path('../../test_helper', __FILE__)

class GithubTest < ActiveSupport::TestCase
  def setup
    @repository = Repository::Github.new(project_id: 1, url: 'https://github.com/farend/redmine_github_repo.git', identifier: 'test_project')
    @scm = @repository.scm
    @repo = "farend/redmine_github_repo"
  end

  def test_fetch_changesets_Githubでchangesetsが追加される場合
    author = OctokitAuthor.new(name: 'author_name')
    rev = OctokitRevision.new(identifier: 'shashasha', scmid: 'shashasha', author: author, paths: nil, time: Time.local(2023, 1, 1, 0, 0, 0, 0), message: 'tmessage')
    changesets = []
    changeset = RepositoryChangeset.new(
      repository: @repository,
      revision: rev.identifier,
      scmid: rev.scmid,
      comitter: rev.author,
      committed_on: rev.time,
      comments: rev.message
    )

    @scm.stub(:revisions, build_mock([rev], []) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
      @repository.stub(:save_revisions!, build_mock([], []) { |revisions, revisions_copy|
        assert_equal [rev], revisions
        changesets << changeset
      }) do
        @repository.fetch_changesets
        extra_info = changesets[0][:repository][:extra_info]
        assert_equal @repository, changesets[0][:repository]  
        assert_equal '2023-01-01T00:00:00Z', extra_info['last_committed_date']
        assert_equal 'shashasha', extra_info['last_committed_id']
      end
    end
  end

  def test_fetch_changesets_Githubでchangesetsに変更が加わる場合
    author = OctokitAuthor.new(name: 'author_name')
    rev_from = OctokitRevision.new(identifier: 'shashafrom', scmid: 'shashafrom', author: author, paths: nil, time: Time.local(2023, 1, 1, 0, 0, 0, 0), message: 'frommessage')
    rev_to = OctokitRevision.new(identifier: 'shashato', scmid: 'shashato', author: author, paths: nil, time: Time.local(2023, 12, 31, 23, 59, 59, 0), message: 'tomessage')
    changeset_from = RepositoryChangeset.new(
      repository: @repository,
      revision: rev_from.identifier,
      scmid: rev_from.scmid,
      comitter: rev_from.author,
      committed_on: rev_from.time,
      comments: rev_from.message
    )
    changeset_to = RepositoryChangeset.new(
      repository: @repository,
      revision: rev_to.identifier,
      scmid: rev_to.scmid,
      comitter: rev_to.author,
      committed_on: rev_to.time,
      comments: rev_to.message
    )
    changesets = [changeset_from]
    
    @scm.stub(:revisions, build_mock([rev_from, rev_to], []) { |path, identifier_from, identifier_to|
      assert_equal '', path
      assert_equal nil, identifier_from
      assert_equal nil, identifier_to
    }) do
      @repository.stub(:save_revisions!, build_mock([], []) { |revisions, revisions_copy|
        assert_equal [rev_from, rev_to], revisions
        changesets[0] = changeset_to
      }) do
        @repository.fetch_changesets
        extra_info = changesets[0][:repository][:extra_info]
        assert_equal @repository, changesets[0][:repository]  
        assert_equal '2023-12-31T23:59:59Z', extra_info['last_committed_date']
        assert_equal 'shashato', extra_info['last_committed_id']
      end
    end
  end

  ## 以下、Octokitのモックに使う部品たち ##
  RepositoryChangeset = Struct.new(:repository, :revision, :scmid, :comitter, :committed_on, :comments, keyword_init: true)

  OctokitRevision = Struct.new(:identifier, :scmid, :author, :committer, :tree, 
  :message, :paths, :time, keyword_init: true)
  OctokitAuthor = Struct.new(:name, keyword_init: true)

  
  def build_mock(*returns, &proc)
    mock = Minitest::Mock.new
    Array.wrap(returns).each do |ret|
      mock.expect(:call, ret, &proc)
    end
    mock
  end

end