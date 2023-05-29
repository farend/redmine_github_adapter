require 'redmine/scm/adapters/abstract_adapter'

module Redmine
  module Scm
    module Adapters
      class GithubAdapter < AbstractAdapter
        class GithubBranch < Branch
          attr_accessor :is_default
        end

        def initialize(url, root_url=nil, login=nil, password=nil, path_encoding=nil)
          super

          ## Get gitlab project
          @project = url.sub(root_url, '').sub(/^\//, '').sub(/\.git$/, '')

          ## Set Gitlab endpoint and token
          Octokit.configure do |c|
            c.api_endpoint = "#{root_url}/api/v3/"
            c.access_token = password
          end

          ## Set proxy
          # proxy = URI.parse(url).find_proxy
          # unless proxy.nil?
          #   Gitlab.http_proxy(proxy.host, proxy.port, proxy.user, proxy.password)
          # end
        end
      end
    end
  end
end
