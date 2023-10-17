require File.expand_path('../../test_helper', __FILE__)

class GithubAdapterTest < ActiveSupport::TestCase
  def setup
    @scm = Redmine::Scm::Adapters::GithubAdapter.new('https://github.com/farend/redmine_github_repo.git')
    @repo = "farend/redmine_github_repo"
  end

  def test_branches_Githubの戻り値が空の場合
    Octokit.stub(:branches, build_mock([]) {|repo, options|
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

    pages = [1, 2]

    Octokit.stub(:branches, build_mock([branch], []) { |repo, options|
      assert_equal @repo, repo
      assert_equal pages.shift, options[:page]
      assert_equal 100, options[:per_page]
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

    pages = [1, 2]

    Octokit.stub(:branches, build_mock(multi_branche, []) { |repo, options|
      assert_equal @repo, repo
      assert_equal pages.shift, options[:page]
      assert_equal 100, options[:per_page]
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
    pages = [1, 2]

    Octokit.stub(:branches, build_mock(multi_branche, []) { |repo, options|
      assert_equal @repo, repo
      assert_equal pages.shift, options[:page]
      assert_equal 100, options[:per_page]
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
    Octokit.stub(:contents, build_mock([]) { |repo, options|
      assert_equal @repo, repo
      assert_equal nil, options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      entries = @scm.entries
      assert_equal 0, entries.length
    end
  end

  def test_entries_Githubの戻り値が1つある場合
    content = OctokitContent.new(name: 'test.md', path: 'farend/redmine_github_repo', type: 'file', size: 256)
    
    Octokit.stub(:contents, build_mock([content], []) { |repo, options|
      assert_equal @repo, repo
      assert_equal nil, options[:path]
      assert_equal 'HEAD', options[:ref]
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
    
    Octokit.stub(:contents, build_mock(contents, []) { |repo, options|
      assert_equal @repo, repo
      assert_equal nil, options[:path]
      assert_equal 'HEAD', options[:ref]
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
    
    Octokit.stub(:contents, build_mock(contents, []) { |repo, options|
      assert_equal @repo, repo
      assert_equal nil, options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      entries = @scm.entries
      assert_equal 'aaa.md', entries[0].name
      assert_equal 'bbb.md', entries[1].name
      assert_equal 'ccc.md', entries[2].name
    end
  end

  def test_entries_Githubのreport_last_commitオプションにtrueが与えられる場合
    content = OctokitContent.new(name: 'test.md', path: 'farend/redmine_github_repo', type: 'file', size: 256)
    lastrev = OctokitRevision.new(identifier: 'shashasha')
    
    Octokit.stub(:contents, build_mock(content, []) { |repo, options|
      assert_equal @repo, repo
      assert_equal nil, options[:path]
      assert_equal 'shashasha', options[:ref]
    }) do
      @scm.stub(:lastrev, build_mock(lastrev, []) { |repo, rev|
        assert_equal @repo, repo
        assert_equal 'shashasha', rev
      }) do
        entries = @scm.entries(nil, 'shashasha', {report_last_commit: true})
        assert_equal 'shashasha', entries[0].lastrev.identifier
      end
    end
  end

  def test_revision_to_sha_GithubにコミットのSHAを渡される場合
    commit = OctokitCommit.new(sha: 'shashasha')
    
    Octokit.stub(:commits, build_mock([commit], []) { |repo, rev, options|
      assert_equal @repo, repo
      assert_equal 'shashasha', rev
      assert_equal 1, options[:per_page]
    }) do
      assert_equal 'shashasha', @scm.revision_to_sha('shashasha')
    end
  end

  def test_revision_to_sha_Githubにブランチ名を渡される場合
    branch = OctokitBranch.new(name: 'main', sha: 'shashasha')
    
    Octokit.stub(:commits, build_mock([branch], []) { |repo, rev, options|
      assert_equal @repo, repo
      assert_equal 'main', rev
      assert_equal 1, options[:per_page]
    }) do
      assert_equal 'shashasha', @scm.revision_to_sha('main')
    end
  end

  def test_lastrev_Githubの戻り値が返ってくる場合
    author = OctokitAuthor.new(name: 'AuthorName')
    committer = OctokitCommiter.new(date: '2023-01-01 00:00:00')
    rev = OctokitRevision.new(identifier: 'shashasha', author: author, committer: committer)
    commit = OctokitCommit.new(sha: 'shashasha', commit: rev )
    
    Octokit.stub(:commits, build_mock([commit], []) { |repo, rev, options|
      assert_equal @repo, repo
      assert_equal 'shashasha', rev
      assert_equal @repo, options[:path]
      assert_equal 1, options[:per_page]
    }) do
      revision = @scm.lastrev('farend/redmine_github_repo', 'shashasha')
      
      assert_equal 'shashasha', revision.identifier
      assert_equal 'AuthorName', revision.author
      assert_equal '2023-01-01 00:00:00', revision.time
    end
  end

  def test_lastrev_Githubの引数pathが与えられない場合
    Octokit.stub(:commits, build_mock([], []) { |repo, rev, options|
      assert_equal nil, repo
      assert_equal 'shashasha', rev
      assert_equal @repo, options[:path]
      assert_equal 1, options[:per_page]
    }) do
      assert_equal nil, @scm.lastrev(nil, 'shashasha')
    end
  end

  def test_lastrev_Githubの引数に該当するコミットが存在しない場合
    Octokit.stub(:commits, build_mock([], []) { |repo, rev, options|
      assert_equal @repo, repo
      assert_equal 'shashasha', rev
      assert_equal @repo, options[:path]
      assert_equal 1, options[:per_page]
    }) do
      assert_equal nil, @scm.lastrev(@repo, 'shashasha')
    end
  end

  def test_get_path_name_Githubの戻り値が存在する場合
    blob = OctokitContent.new(sha: 'shashasha', path: 'farend/redmine_github_repo')
    tree = OctokitTree.new(tree:[blob], sha: 'shashasha')
    commit = OctokitCommit.new(sha: 'shashasha', commit: OctokitRevision.new(tree: tree))
    
    Octokit.stub(:commits, build_mock([commit], []) { |repo|
      assert_equal @repo, repo
    }) do
      Octokit.stub(:tree, build_mock(tree, []) { |repo, sha|
        assert_equal @repo, repo
        assert_equal 'shashasha', sha
      }) do
        assert_equal @repo, @scm.get_path_name('shashasha')
      end
    end
  end

  def test_revisions_Githubの戻り値が1つある場合
    author = OctokitAuthor.new(name: 'AuthorName')
    committer = OctokitCommiter.new(date: '2023-01-01 00:00:00')
    parent = OctokitCommit.new(sha: 'shashafrom')
    rev = OctokitRevision.new(identifier: 'shashato', author: author, committer: committer, message: 'commit message')
    commit = OctokitCommit.new(sha: 'shashato', commit: rev, parents: [parent])
    options = { path: @repo, per_page: 1 }
    Octokit.stub(:commits, build_mock([commit], []) { |repo|
      assert_equal @repo, repo
    }) do
      revisions = @scm.revisions(@repo, 'shashato', 'shashafrom', options )

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

    options = { path: @repo, per_page: 1 }
    Octokit.stub(:commits, build_mock(commits, []) { |repo|
      assert_equal @repo, repo
    }) do
      revisions = @scm.revisions(@repo, 'shashato', 'shashafrom', options )

      assert_equal 3, revisions.size

      revisions.each_with_index {|rev, i|
        assert_equal "shashasha#{i+1}", rev.identifier
        assert_equal "2023-01-00 0#{i}:00:00", rev.time
        assert_equal i + 1, rev.parents.size
      }
    end
  end

  def test_get_filechanges_and_append_to_Githubに1つのrevisisonが渡される場合
    add_file = TestFile.new(status: "added", filename: "add.md")
    mod_file = TestFile.new(status: "modified", filename: "mod.md")
    rev = OctokitRevision.new(identifier: "shashasha", paths: nil)
    commit = OctokitCommit.new(sha: "shashasha", files: [add_file, mod_file])

    Octokit.stub(:commit, build_mock(commit, []) { |repo, sha|
      assert_equal @repo, repo
      assert_equal "shashasha", sha
    }) do
      @scm.get_filechanges_and_append_to([rev])
      assert_equal 'A', rev.paths[0][:action]
      assert_equal 'add.md', rev.paths[0][:path]
      assert_equal 'M', rev.paths[1][:action]
      assert_equal 'mod.md', rev.paths[1][:path]
    end
  end

  def test_diff_Githubに追加差分のあるファイルパスとコミットSHAが渡される場合
    file = TestFile.new(status: 'added', filename: "farend/redmine_github_repo/README.md")
    cat = "add_line"
    commit = OctokitCommit.new(sha: 'shashasha', files: [file])

    added_diffs = [
      "diff",
      "--- /dev/null",
      "+++ b/#{file.filename}",
      "@@ -0,0 +1,2 @@",
      "+#{cat}"
    ]

    Octokit.stub(:commit, build_mock(commit, []) { |repo, identifier_from, options|
      assert_equal @repo, repo
      assert_equal 'shashasha', identifier_from
      assert_equal @repo, options[:path]
    }) do
      @scm.stub(:cat, build_mock(cat, []) { |path, identifier|
        assert_equal 'farend/redmine_github_repo/README.md', path
        assert_equal 'shashasha', identifier
      }) do
        diffs = @scm.diff(@repo, "shashasha")
        assert_equal added_diffs, diffs
      end
    end
  end

  def test_diff_Githubにファイル名変更差分のあるファイルパスとコミットshaが渡される場合
    file_from = TestFile.new(status: 'added', filename: "farend/redmine_github_repo/README.md")
    file_to = TestFile.new(status: 'renamed', filename: "farend/redmine_github_repo/RENAME.md", previous_filename: "farend/redmine_github_repo/README.md")
    cat = "add_line"
    commit_from = OctokitCommit.new(sha: 'shashafrom')
    commit_to = OctokitCommit.new(sha: 'shashato')
    compare = OctokitCompare.new(base_commit: commit_from, commits: [commit_to], files: [file_to, file_from])

    renamed_diffs = [
      "diff",
      "--- a/#{file_from.filename}",
      "+++ b/#{file_to.filename}",
      "diff",
      "--- /dev/null",
      "+++ b/#{file_from.filename}",
      "@@ -0,0 +1,2 @@",
      "+#{cat}"
    ]

    ids = ['shashafrom', 'shashato']

    Octokit.stub(:compare, build_mock(compare, []) { |repo, identifier_to, identifier_from, options|
      assert_equal @repo, repo
      assert_equal 'shashato', identifier_to
      assert_equal 'shashafrom', identifier_from
      assert_equal @repo, options[:path]
    }) do
      @scm.stub(:cat, build_mock(cat, []) { |path, identifier|
        assert_equal 'farend/redmine_github_repo/README.md', path
        assert_equal ids.shift, identifier
      }) do
        diffs = @scm.diff(@repo, 'shashafrom', 'shashato')
        assert_equal renamed_diffs, diffs
      end
    end
  end

  def test_diff_Githubに変更差分のあるファイルパスとコミットshaが渡される場合
    file_from = TestFile.new(status: 'added', filename: "farend/redmine_github_repo/README.md")
    file_to = TestFile.new(status: 'modifies', filename: "farend/redmine_github_repo/README.md", patch:'+mod_line')
    cat = "add_line"
    commit_from = OctokitCommit.new(sha: 'shashafrom')
    commit_to = OctokitCommit.new(sha: 'shashato')
    compare = OctokitCompare.new(base_commit: commit_from, commits: [commit_to], files: [file_to, file_from])

    modified_diffs = [
      "diff",
      "--- a/#{file_from.filename}",
      "+++ b/#{file_to.filename}",
      "#{file_to.patch}",
      "diff",
      "--- /dev/null",
      "+++ b/#{file_from.filename}",
      "@@ -0,0 +1,2 @@",
      "+#{cat}"
    ]

    ids = ['shashafrom', 'shashato']

    Octokit.stub(:compare, build_mock(compare, []) { |repo, identifier_to, identifier_from, options|
      assert_equal @repo, repo
      assert_equal 'shashato', identifier_to
      assert_equal 'shashafrom', identifier_from
      assert_equal @repo, options[:path]
    }) do
      @scm.stub(:cat, build_mock(cat, []) { |path, identifier|
        assert_equal 'farend/redmine_github_repo/README.md', path
        assert_equal ids.shift, identifier
      }) do
          diffs = @scm.diff(@repo, "shashafrom", "shashato")
          assert_equal modified_diffs, diffs
      end
    end
  end

  def test_diff_Githubに削除差分のあるファイルパスとコミットshaが渡される場合
    file_from = TestFile.new(status: 'added', filename: "farend/redmine_github_repo/README.md")
    file_to = TestFile.new(status: 'removed', filename: "farend/redmine_github_repo/README.md", patch:'-add_line')
    cat = "add_line"
    commit_from = OctokitCommit.new(sha: 'shashafrom')
    commit_to = OctokitCommit.new(sha: 'shashato')
    compare = OctokitCompare.new(base_commit: commit_from, commits: [commit_to], files: [file_from, file_to])

    removed_diffs = [
      "diff",
      "--- /dev/null",
      "+++ b/#{file_from.filename}",
      "@@ -0,0 +1,2 @@",
      "+#{cat}",
      "diff",
      "--- a/#{file_from.filename}",
      "+++ /dev/null",
      "@@ -1,2 +0,0 @@",
      "-[]"
    ]

    ids = ['shashafrom', 'shashato']

    Octokit.stub(:compare, build_mock(compare, []) { |repo, identifier_to, identifier_from, options|
      assert_equal @repo, repo
      assert_equal 'shashato', identifier_to
      assert_equal 'shashafrom', identifier_from
      assert_equal @repo, options[:path]
    }) do
      @scm.stub(:cat, build_mock(cat, []) { |path, identifier|
        assert_equal 'farend/redmine_github_repo/README.md', path
        assert_equal ids.shift, identifier
      }) do
          diffs = @scm.diff(@repo, "shashafrom", "shashato")
          assert_equal removed_diffs, diffs
      end
    end
  end

  def test_default_branch_Githubの戻り値が存在する場合
    branch = OctokitBranch.new(name: 'main', commit: OctokitCommit.new(sha: 'shashasha'))
    Octokit.stub(:branches, build_mock([branch], []) { |repo|
      assert_equal @repo, repo
    }) do
      assert_equal 'main', @scm.default_branch
    end
  end

  def test_default_branch_Githubの戻り値が存在しない場合
    Octokit.stub(:branches, build_mock([], []) { |repo|
      assert_equal @repo, repo
    }) do
      assert_equal nil, @scm.default_branch
    end
  end

  def test_entry_Githubに引数を渡す場合
    content = OctokitContent.new(name: 'README.md', path: @repo, type: 'file', size: 256)
    lastrev = OctokitRevision.new(identifier:'shashasha')

    Octokit.stub(:contents, build_mock([content], []) { |repo, options|
      assert_equal @repo, repo
      assert_equal 'README.md', options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      @scm.stub(:lastrev, build_mock(lastrev, []) { |repos, rev|
        assert_equal @repo, repos
      }) do
        entry = @scm.entry('README.md')
        assert_equal 'README.md', entry.name
        assert_equal 'file', entry.kind
        assert_equal @repo, entry.path
        assert_equal 256, entry.size
      end
    end
  end

  def test_entry_Githubに引数を渡さない場合
    Octokit.stub(:contents, build_mock([], []) { |repo, options|
      assert_equal @repo, repo
      assert_equal @repo, options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      entry = @scm.entry
      assert_equal 'dir', entry.kind
      assert_equal '', entry.path
    end
  end

  def test_cat_Githubで取得ファイルのエンコードが不要な場合
    blob = OctokitContent.new(path: @repo, sha: 'shashasha', download_url: 'http://download/url',
                              encoding: 'utf-8', content: 'test_content')
    get = OctokitGet.new(headers:{ "content-type" => 'text/html; charset=utf-8'})
    Octokit.stub(:contents, build_mock(blob, []) { |path, options|
      assert_equal @repo, path
      assert_equal @repo, options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      Octokit.stub(:get, build_mock(get, []) { |url|
        assert_equal 'http://download/url', url
      }) do
        Octokit.stub(:last_response, build_mock(get, [])) do
          assert_equal 'test_content', @scm.cat(@repo)
        end
      end
    end
  end

  def test_cat_Githubで取得ファイルのエンコードが必要な場合
    blob = OctokitContent.new(path: @repo, sha: 'shashasha', download_url: 'http://download/url',
                              encoding: 'base64', content: 'dGVzdF9jb250ZW50')
    get = OctokitGet.new(headers:{ "content-type" => 'text/html; charset=base64'})
    Octokit.stub(:contents, build_mock(blob, []) { |path, options|
      assert_equal @repo, path
      assert_equal @repo, options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      Octokit.stub(:get, build_mock(get, []) { |url|
        assert_equal 'http://download/url', url
      }) do
        Octokit.stub(:last_response, build_mock(get, [])) do
          assert_equal 'test_content', @scm.cat(@repo)
        end
      end
    end
  end

  def test_cat_Githubで取得ファイルがバイナリ形式の場合
    blob = OctokitContent.new(path: @repo, sha: 'shashasha', download_url: 'http://download/url')
    get = OctokitGet.new(headers:{ "content-type" => 'binary'})
    Octokit.stub(:contents, build_mock(blob, []) { |path, options|
      assert_equal @repo, path
      assert_equal @repo, options[:path]
      assert_equal 'HEAD', options[:ref]
    }) do
      Octokit.stub(:get, build_mock(get, []) { |url|
        assert_equal 'http://download/url', url
      }) do
        Octokit.stub(:last_response, build_mock(get, [])) do
          assert_equal '', @scm.cat(@repo)
        end
      end
    end
  end

  ## 以下、Octokitのモックに使う部品たち ##

  OctokitBranch = Struct.new(:name, :commit, :sha, keyword_init: true)
  OctokitCommit = Struct.new(:sha, :commit, :parents, :files, keyword_init: true)
  OctokitContent = Struct.new(:sha, :name, :path, :type, :size, :download_url, 
                              :content, :encoding, keyword_init: true)
  OctokitRevision = Struct.new(:identifier, :author, :committer, :tree, 
                               :message, :paths, keyword_init: true)
  OctokitAuthor = Struct.new(:name, keyword_init: true)
  OctokitCommiter = Struct.new(:date, keyword_init: true)
  OctokitTree = Struct.new(:tree, :sha, keyword_init: true)
  OctokitCompare = Struct.new(:base_commit, :commits, :files, keyword_init: true)
  OctokitGet = Struct.new(:headers, keyword_init: true) 
  TestFile = Struct.new(:status, :filename, :previous_filename, 
                        :from_revision, :patch, keyword_init: true)

  def build_mock(*returns, &proc)
    mock = Minitest::Mock.new
    Array.wrap(returns).each do |ret|
      mock.expect(:call, ret, &proc)
    end
    mock
  end
end
