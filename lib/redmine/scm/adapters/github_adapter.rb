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
          # Octokit.configure do |c|
          #   c.api_endpoint = "#{root_url}/api/v3/"
          #   c.access_token = password
          # end

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
      end
    end
  end
end
