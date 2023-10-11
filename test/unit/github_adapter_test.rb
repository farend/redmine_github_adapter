require File.expand_path('../../test_helper', __FILE__)

class GithubAdapterTest < ActiveSupport::TestCase
  def setup
    @scm = Redmine::Scm::Adapters::GithubAdapter.new('https://github.com/farend/redmine_github_repo.git')
    @repo = "farend/redmine_github_repo"
    @repos = [@repo]
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
    branch = OctokitBranch.new(name: 'main', commit: OctokitCommit.new(sha: 'shashasha'))

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

  def test_branches_Githubの戻り値が複数ある場合
    multi_branche = ['main', 'dev', 'feat'].sort.map.with_index{ |name, i|
      OctokitBranch.new(name: name, commit: OctokitCommit.new(sha: "shashasha#{i}"))
    }

    Octokit.stub(:branches, build_mock(multi_branche, []) { |repos, options|
      assert options[:page]
    }) do
      branches = @scm.branches

      assert_equal multi_branche.length, branches.length
      branches.each.with_index do |branch,i|
        assert_equal multi_branche[i].name, branch.to_s
        assert_equal "shashasha#{i}", branch.revision
        assert_equal "shashasha#{i}", branch.scmid
      end
    end
  end

  def test_branches_Githubに未ソートのブランチが与えられた場合
    multi_branche = ['bbb', 'ccc', 'aaa'].map{ |name|
      OctokitBranch.new(name: name, commit: OctokitCommit.new(sha: "sha#{name}"))
    }

    sorted_multi_branche =  ['aaa', 'bbb', 'ccc']

    Octokit.stub(:branches, build_mock(multi_branche, []) { |repos, options|
      assert options[:page]
    }) do
      branches = @scm.branches

      assert_equal multi_branche.length, branches.length
      branches.each.with_index do |branch, i|
        assert_equal sorted_multi_branche[i], branch.to_s
        assert_equal "sha#{sorted_multi_branche[i]}", branch.revision
        assert_equal "sha#{sorted_multi_branche[i]}", branch.scmid
      end
    end
  end

  def test_entries_Githubの戻り値が空の場合
    Octokit.stub(:contents, build_mock([]) { |repos, path, ref|
      assert_equal @repo, repos
    }) do
      entries = @scm.entries
      assert_equal 0, entries.length
    end
  end

  def test_entries_Githubの戻り値が1つある場合
    content = OctokitContent.new(name: 'test.md', path: 'farend/redmine_github_repo', type: 'file', size: 256)
    
    Octokit.stub(:contents, build_mock([content], []) { |repos, path, ref|
      assert_equal @repo, repos
    }) do
      entries = @scm.entries
      assert_equal 1, entries.length
      assert_equal 'test.md', entries[0].name
      assert_equal 'farend/redmine_github_repo', entries[0].path
      assert_equal 'file', entries[0].kind
      assert_equal 256, entries[0].size
    end
  end

  def test_entries_Githubの戻り値が複数ある場合
    contents = ['test.md', 'test.txt'].sort.map{ |name|
      OctokitContent.new(name: name, path: 'farend/redmine_github_repo', type: 'file', size: 256)
    }
    
    Octokit.stub(:contents, build_mock(contents, []) { |repos, path, ref|
      assert_equal @repo, repos
    }) do
      entries = @scm.entries
      assert_equal 2, entries.length
      assert_equal 'test.md', entries[0].name
      assert_equal 'farend/redmine_github_repo', entries[0].path
      assert_equal 'test.txt', entries[1].name
      assert_equal 'farend/redmine_github_repo', entries[1].path
    end
  end

  def test_entries_Githubに未ソートのコンテンツが与えられた場合
    contents = ['bbb.md', 'ccc.md', 'aaa.md'].map{ |name|
      OctokitContent.new(name: name, path: 'farend/redmine_github_repo', type: 'file', size: 256)
    }
    
    Octokit.stub(:contents, build_mock(contents, []) { |repos, path, ref|
      assert_equal @repo, repos
    }) do
      entries = @scm.entries
      assert_equal 'aaa.md', entries[0].name
      assert_equal 'bbb.md', entries[1].name
      assert_equal 'ccc.md', entries[2].name
    end
  end

  def test_entries_Githubでオプションreport_last_commitがtrueの場合
    content = OctokitContent.new(name: 'test.md', path: 'farend/redmine_github_repo', type: 'file', size: 256)
    lastrev = OctokitRevision.new(identifier: 'shashasha')
    
    Octokit.stub(:contents, build_mock(content, []) { |repos, path, ref|
      assert_equal @repo, repos
    }) do
      @scm.stub(:lastrev, build_mock(lastrev, []) { |repos, rev|
        assert_equal @repo, repos
      }) do
        entries = @scm.entries(nil, 'shashasha', {report_last_commit: true})
        assert_equal 'shashasha', entries[0].lastrev.identifier
      end
    end
  end

  def test_revision_to_sha_GithubにコミットのSHAを渡した場合
    commit = OctokitCommit.new(sha: 'shashasha')
    opt = { per_page: 1 }
    
    Octokit.stub(:commits, build_mock([commit], []) { |repos, rev, opt|
      assert_equal @repo, repos
    }) do
      assert_equal 'shashasha', @scm.revision_to_sha('shashasha')
    end
  end

  def test_revision_to_sha_Githubにブランチ名を渡した場合
    branch = OctokitBranch.new(name: 'main', sha: 'shashasha')
    opt = { per_page: 1 }
    
    Octokit.stub(:commits, build_mock([branch], []) { |repos, rev, opt|
      assert_equal @repo, repos
      assert_equal 'main', rev
    }) do
      assert_equal 'shashasha', @scm.revision_to_sha('main')
    end
  end

  def test_lastrev_Githubの戻り値が返ってくる場合
    author = OctokitAuthor.new(name: 'AuthorName')
    committer = OctokitCommiter.new(date: '2023-01-01 00:00:00')
    rev = OctokitRevision.new(identifier: 'shashasha', author: author, committer: committer)
    commit = OctokitCommit.new(sha: 'shashasha', commit: rev )
    
    Octokit.stub(:commits, build_mock([commit], []) { |repos, rev|
      assert_equal @repo, repos
    }) do
      revision = @scm.lastrev('farend/redmine_github_repo', 'shashasha')
      
      assert_equal 'shashasha', revision.identifier
      assert_equal 'AuthorName', revision.author
      assert_equal '2023-01-01 00:00:00', revision.time
    end
  end

  def test_lastrev_Githubの引数pathが与えられない場合
    Octokit.stub(:commits, build_mock([], []) { |repos, rev|
      assert_equal @repo, repos
    }) do
      assert_equal nil, @scm.lastrev(nil, 'shashasha')
    end
  end

  def test_lastrev_Githubの引数に該当するコミットが存在しない場合
    Octokit.stub(:commits, build_mock([], []) { |repos, rev|
      assert_equal @repo, repos
    }) do
      assert_equal nil, @scm.lastrev('farend/redmine_github_repo', 'shashasha')
    end
  end

  def test_get_path_name_Githubの戻り値が存在する場合
    blob = OctokitContent.new(sha: 'shashasha', path: 'farend/redmine_github_repo')
    tree = OctokitTree.new(tree:[blob], sha: 'shashasha')
    commit = OctokitCommit.new(sha: 'shashasha', commit: OctokitRevision.new(tree: tree))
    
    Octokit.stub(:commits, build_mock([commit], []) { |repos, rev, opt|
      assert_equal @repo, repos
    }) do
      Octokit.stub(:tree, build_mock(tree, []) { |repos, sha|
        assert_equal @repo, repos
        assert_equal 'shashasha', sha
      }) do
        assert_equal 'farend/redmine_github_repo', @scm.get_path_name('shashasha')
      end
    end
  end

  def test_revisions_Githubの戻り値が1つある場合
    author = OctokitAuthor.new(name: 'AuthorName')
    committer = OctokitCommiter.new(date: '2023-01-01 00:00:00')
    parent = OctokitCommit.new(sha: 'shashafrom')
    rev = OctokitRevision.new(identifier: 'shashato', author: author, committer: committer, message: 'commit message')
    commit = OctokitCommit.new(sha: 'shashato', commit: rev, parents: [parent])
    opt = { path: @repo, per_page: 1 }
    Octokit.stub(:commits, build_mock([commit], []) { |repos, rev|
      assert_equal @repo, repos
    }) do
      revisions = @scm.revisions(@repo, 'shashato', 'shashafrom', opt )

      assert_equal 1, revisions.size
      assert_equal 'shashato', revisions[0].identifier
      assert_equal 'commit message', revisions[0].message
      assert_equal '2023-01-01 00:00:00', revisions[0].time
      assert_equal 'shashafrom', revisions[0].parents[0]
    end
  end

  def test_revisions_Githubの戻り値が複数ある場合
    parents = []
    commits = 3.times.map { |i|
      author = OctokitAuthor.new(name: "Author#{i}")
      committer = OctokitCommiter.new(date: "2023-01-00 0#{i}:00:00")
      parents << OctokitCommit.new(sha: "shashasha#{i}")
      rev = OctokitRevision.new(identifier: "shashasha#{i+1}", author: author, committer: committer, message: 'commit message')
      OctokitCommit.new(sha: "shashasha#{i+1}", commit: rev, parents: parents.dup)
    }

    opt = { path: @repo, per_page: 1 }
    Octokit.stub(:commits, build_mock(commits, []) { |repos, rev|
      assert_equal @repo, repos
    }) do
      revisions = @scm.revisions(@repo, 'shashato', 'shashafrom', opt )
      
      assert_equal 3, revisions.size

      revisions.each_with_index {|rev, i|
        assert_equal "shashasha#{i+1}", rev.identifier
        assert_equal "2023-01-00 0#{i}:00:00", rev.time
        assert_equal i + 1, rev.parents.size
      }
    end
  end

  def test_revisions_Githubのallオプションにtrueが与えられる場合
    parents = []
    commits = 3.times.map { |i|
      author = OctokitAuthor.new(name: "Author#{i}")
      committer = OctokitCommiter.new(date: "2023-01-00 0#{i}:00:00")
      parents << OctokitCommit.new(sha: "shashasha#{i}")
      rev = OctokitRevision.new(identifier: "shashasha#{i+1}", author: author, 
                                committer: committer, message: 'commit message')
      OctokitCommit.new(sha: "shashasha#{i+1}", commit: rev, parents: parents.dup)
    }
    opt = { path: @repo, per_page: 1, all: true, last_committed_id: 'shashasha3'}
    Octokit.stub(:commits, build_mock(commits, []) { |repos, rev|
      assert_equal @repo, repos
    }) do
      revisions = @scm.revisions(@repo, 'shashasha2', 'shashasha3', opt )
      
      assert_equal 0, revisions.size
    end
  end

  def test_get_filechanges_and_append_to_Githubにrevisionが渡される場合
    add_file = TestFile.new(status: "added", filename: "add.md")
    mod_file = TestFile.new(status: "modified", filename: "mod.md")
    rev = OctokitRevision.new(identifier: "shashasha", paths: nil)
    commit = OctokitCommit.new(sha: "shashasha", files: [add_file, mod_file])

    Octokit.stub(:commit, build_mock(commit, []) { |repos, sha|
      assert_equal @repo, repos
    }) do
      @scm.get_filechanges_and_append_to([rev])
      assert_equal 'A', rev.paths[0][:action]
      assert_equal 'add.md', rev.paths[0][:path]
      assert_equal 'M', rev.paths[1][:action]
      assert_equal 'mod.md', rev.paths[1][:path]
    end
  end

  ## 以下、Octokitのモックに使う部品たち ##

  OctokitBranch = Struct.new(:name, :commit, :sha, keyword_init: true)
  OctokitCommit = Struct.new(:sha, :commit, :parents, :files, keyword_init: true)
  OctokitContent = Struct.new(:sha, :name, :path, :type, :size, :download_url, keyword_init: true)
  OctokitRevision = Struct.new(:identifier, :author, :committer, :tree, :message, :paths, keyword_init: true)
  OctokitAuthor = Struct.new(:name, keyword_init: true)
  OctokitCommiter = Struct.new(:date, keyword_init: true)
  OctokitTree = Struct.new(:tree, :sha, keyword_init: true)
  TestFile = Struct.new(:status, :filename, :from_revision, keyword_init: true)

  def build_mock(*returns, &proc)
    mock = Minitest::Mock.new
    Array.wrap(returns).each do |ret|
      mock.expect(:call, ret, &proc)
    end
    mock
  end
end
