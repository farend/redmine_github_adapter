require 'redmine/scm/adapters/abstract_adapter'

module Redmine
  module Scm
    module Adapters
      class GithubAdapter < AbstractAdapter
        class GithubBranch < Branch
          attr_accessor :is_default
        end

        PER_PAGE = 50
        MAX_PAGES = 10

        def initialize(url, root_url=nil, login=nil, password=nil, path_encoding=nil)
          super

          ## Get github project
          @project = url.sub(root_url, '').sub(/^\//, '').sub(/\.git$/, '')
          @repos = url.gsub("https://github.com/", '')

          ## Set Github endpoint and token
          Octokit.configure do |c|
            c.access_token = password
          end

          ## Set proxy
          # proxy = URI.parse(url).find_proxy
          # unless proxy.nil?
          #   Gitlab.http_proxy(proxy.host, proxy.port, proxy.user, proxy.password)
          # end
        end

        def branches
          return @branches if @branches
          @branches = []
          1.step do |i|
            github_branches = Octokit.branches(@repos, {page: i, per_page: PER_PAGE})
            break if github_branches.length == 0
            github_branches.each do |github_branch|
              bran = GithubBranch.new(github_branch.name)
              bran.revision = github_branch.commit.sha
              bran.scmid = github_branch.commit.sha
              @branches << bran
            end
          end
          @branches.sort!
        end

        def entries(path=nil, identifier=nil, options={})
          Rails.logger.debug "debug; 9"
          path ||= ''
          identifier = 'HEAD' if identifier.nil?

          entries = Entries.new
          1.step do |i|
            files = Octokit.tree(@repos, identifier).tree
            files = files.select {|file| file.path == path}
            break if files.length == 0

            files.each do |file|
              full_path = file.path
              size = nil
              unless (file.type == "tree")
                # 相当するものがないのでとりあえず飛ばす。
                # github_get_file = Gitlab.get_file(@project, full_path, identifier)
                # size = gitlab_get_file.size
              end
              entries << Entry.new({
                :name => file.path.dup,
                :path => file.path.dup,
                :kind => (file.type == "tree") ? 'dir' : 'file',
                :size => (file.type == "tree") ? nil : size,
                :lastrev => options[:report_last_commit] ? lastrev(full_path, identifier) : Revision.new
              }) unless entries.detect{|entry| entry.name == file.path}
            end
          end
          entries.sort_by_name

        end

        def revisions(path, identifier_from, identifier_to, options={})
          revs = Revisions.new
          per_page = PER_PAGE
          per_page = options[:limit].to_i if options[:limit]
          all = false
          all = options[:all] if options[:all]

          if all
            ## STEP 1: Seek start_page
            start_page = 1
            0.step do |i|
              start_page = i * MAX_PAGES + 1
              github_commits = Octokit.commits(@repos, {all: true, page: start_page, per_page: per_page})
              if github_commits.length < per_page
                start_page = start_page - MAX_PAGES if i > 0
                break
              end
            end

            ## Step 2: Get the commits from start_page
            start_page.step do |i|
              github_commits = Octokit.commits(@repos, {all: true, page: i, per_page: per_page})
              break if github_commits.length == 0
              github_commits.each do |github_commit|
                files=[]
                github_commits.delete(github_commit).each do |github_commit_compared|
                  if github_commit_compared.first == :sha
                    commit_diff = Octokit.compare(@repos, github_commit_compared.last, github_commit.sha)
                    files << commit_diff.files
                  end
                end
                revision = Revision.new({
                  :identifier => github_commit.sha,
                  :scmid      => github_commit.sha,
                  :author     => github_commit.author.login,
                  :time       => github_commit.commit.committer.date,
                  :message    => github_commit.commit.message,
                  :paths      => files,
                  :parents    => github_commit.parents.map(&:sha)
                })
                revs << revision
              end
            end
          else
            github_commits = Octokit.commits(@repos, identifier_to, { per_page: per_page })
            github_commits.each do |github_commit|
              revision = Revision.new({
                :identifier => github_commit.sha,
                :scmid      => github_commit.sha,
                :author     => github_commit.author.login,
                :time       => github_commit.commit.committer.date,
                :message    => github_commit.commit.message,
                :paths      => [],
                :parents    => github_commit.parents.map(&:sha)
              })
              revs << revision
            end
          end

          revs.sort! do |a, b|
            a.time <=> b.time
          end
          Rails.logger.debug "debug; 13"

          Rails.logger.debug revs

          revs

        end


      end
    end
  end
end
