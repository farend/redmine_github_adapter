require 'redmine/scm/adapters/abstract_adapter'

module Redmine
  module Scm
    module Adapters
      class GithubAdapter < AbstractAdapter
        class GithubBranch < Branch
          attr_accessor :is_default
        end
      end
    end
  end
end
