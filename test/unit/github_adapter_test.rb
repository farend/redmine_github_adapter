require File.expand_path('../../test_helper', __FILE__)

class GithubAdapterTest < ActiveSupport::TestCase
  def setup
    @scm = Redmine::Scm::Adapters::GithubAdapter.new('https://github.com/farend/redmine_github_repo.git')
    @repo = "farend/redmine_github_repo"
  end

  def test_branches_Githubの戻り値が空の場合
    Octokit.stub(:branches, build_mock([]) {|repo, options|
      # 引数のアサーションをしておく
      assert_equal @repo, repo
      assert_equal 1, options[:page]
      assert_equal 100, options[:per_page]
    }) do
      branches = @scm.branches

      assert_equal 0, branches.length
    end
  end

  def test_branches_Githubの戻り値が1つある場合
    branch = OctokitBranch.new(name: 'main', commit: OctkoitCommit.new(sha: 'shashasha'))

    Octokit.stub(:branches, build_mock([branch], []) { |repos, options|
      assert options[:page]
    }) do
      branches = @scm.branches

      assert_equal 1, branches.length
      assert_equal 'main', branches[0].to_s
      assert_equal 'shashasha', branches[0].revision
      assert_equal 'shashasha', branches[0].scmid
    end
  end

  ## 以下、Octokitのモックに使う部品たち ##

  OctokitBranch = Struct.new(:name, :commit, keyword_init: true)
  OctkoitCommit = Struct.new(:sha, keyword_init: true)

  def build_mock(*returns, &proc)
    mock = Minitest::Mock.new
    Array.wrap(returns).each do |ret|
      mock.expect(:call, ret, &proc)
    end
    mock
  end
end
