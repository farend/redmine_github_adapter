require 'redmine/scm/adapters/abstract_adapter'

module Redmine
  module Scm
    module Adapters
      class GithubAdapter < AbstractAdapter
        GIT_DEFAULT_BRANCH_NAMES = %w[main master].freeze
        class GithubBranch < Branch
          attr_accessor :is_default
        end

        PER_PAGE = 50
        MAX_PAGES = 10

        def initialize(url, root_url=nil, login=nil, password=nil, path_encoding=nil)
          super

          ## Get github project
          @project = url.sub(root_url, '').sub(/^\//, '').sub(/\.git$/, '')
          @repos = url.gsub("https://github.com/", '').gsub(/\/$/, '')

          ## Set Github endpoint and token
          Octokit.configure do |c|
            c.access_token = password
          end

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
          identifier = 'HEAD' if identifier.nil?

          entries = Entries.new

          files = Octokit.tree(@repos, (path.present? ? path : identifier)).tree
          unless files.length == 0
            files.each do |file|
              full_path = file.path
              entries << Entry.new({
                :name => file.path.dup,
                :path => file.sha.dup,
                :kind => (file.type == "tree") ? 'dir' : 'file',
                :size => (file.type == "tree") ? nil : file.size,
                :lastrev => options[:report_last_commit] ? lastrev(full_path, identifier) : Revision.new
              }) unless entries.detect{|entry| entry.name == file.path}
            end
          end
          entries.sort_by_name

        end


        def lastrev(path, rev)
          return nil if path.nil?
          github_commits = Octokit.commits(@repos, rev, { path: path, per_page: 1 })
          github_commits.each do |github_commit|
            return Revision.new({
              :identifier => github_commit.sha,
              :scmid      => github_commit.sha,
              :author     => github_commit.author.login,
              :time       => github_commit.commit.committer.date,
              :message    => nil,
              :paths      => nil
            })
          end
          return nil
        end

        def get_path_name(path)
          Octokit.commits(@repos).map do |c|
            Octokit.tree(@repos, c.commit.tree.sha).tree.map{|b| [b.sha, b.path] }
          end.flatten.each_slice(2).to_h[path]
        end
        private :get_path_name

        def revisions(path, identifier_from, identifier_to, options={})
          rev_path = get_path_name(path) || ""
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
              github_commits = Octokit.commits(@repos, {all: true, path: rev_path, page: start_page, per_page: per_page})
              if github_commits.length < per_page
                start_page = start_page - MAX_PAGES if i > 0
                break
              end
            end

            ## Step 2: Get the commits from start_page
            start_page.step do |i|
              github_commits = Octokit.commits(@repos, {all: true, path: rev_path, page: i, per_page: per_page})
              break if github_commits.length == 0
              github_commits.each do |github_commit|
                commit_diff = Octokit.commit(@repos, github_commit.sha)
                files = commit_diff.files.map do |f|
                  h = {}
                  h[:action] = case f.status
                  when "removed"
                    "D"
                  when "added"
                    "A"
                  when "modified"
                    "M"
                  else
                    "M"
                  end

                  h[:path] = f.filename
                  h[:from_path] = f[:from_revision] = nil
                  h
                end || []
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
            github_commits = Octokit.commits(@repos, identifier_to, { path: rev_path, per_page: per_page })
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
          revs
        end

        def diff(path, identifier_from, identifier_to=nil)
          path ||= ''
          diff = []

          github_diffs = []

          if identifier_to.nil?
            github_diffs = Octokit.commit(@repos, identifier_from).files
          else
            github_diffs = Octokit.compare(@repos, identifier_to, identifier_from).files
          end

          github_diffs.each do |github_diff|
            if identifier_to.nil? && path.length > 0
              next unless github_diff.map(&:sha).include? path
            end

            case github_diff.status
            when "renamed"
              diff << "diff"
              diff << "--- a/#{github_diff.previous_filename}"
              diff << "+++ b/#{github_diff.filename}"
            when "added"
              diff << "diff"
              diff << "--- /dev/null"
              diff << "+++ b/#{github_diff.filename}"
              diff << "@@ -0,0 +1,2 @@"
              cat(github_diff.sha, nil).split("\n").each do |line|
                diff << "+#{line}"
              end
            when "removed"
              diff << "diff"
              diff << "--- a/#{github_diff.filename}"
              diff << "+++ /dev/null"
              diff << "@@ -1,2 +0,0 @@"
              cat(github_diff.sha, nil).split("\n").each do |line|
                diff << "-#{line}"
              end
            else
              diff << "diff"
              diff << "--- a/#{github_diff.filename}"
              diff << "+++ b/#{github_diff.filename}"
              diff << github_diff.patch&.split("\n")
            end
          end
          diff.flatten!
          diff.deep_dup

        end

        def annotate(path, identifier=nil)
          nil
        end

        def default_branch
          return if branches.blank?

          (
            branches.detect(&:is_default) ||
            branches.detect {|b| GIT_DEFAULT_BRANCH_NAMES.include?(b.to_s)} ||
            branches.first
          ).to_s
        end

        def entry(path=nil, identifier=nil)
          if path.blank?
            # Root entry
            Entry.new(:path => '', :kind => 'dir')
          else
            begin
              blob = Octokit.blob(@repos, path)
            rescue "Octokit::NotFound"
              blob = Octokit.tree(@repos, path)
            end
            Entry.new({
                :name => blob.filename,
                :path => blob.filename,
                :kind => (blob.type == "tree") ? 'dir' : 'file',
                :size => (blob.type == "tree") ? nil : blob.size,
              })
          end
        end

        def cat(path, identifier=nil)
          identifier = 'HEAD' if identifier.nil?

          blob = Octokit.blob(@repos, path)
          content = blob.content
          content = blob.encoding == "base64" ? Base64.decode64(content) : content

          content.force_encoding 'utf-8'
        end

        def valid_name?(name)
          true
        end

        module ScmData
          def self.binary?(data)
            url = c.contents("NaCl-Ltd/redmine_github_adapter", path: "init.rb")[:download_url]
            #=> "https://raw.githubusercontent.com/NaCl-Ltd/redmine_github_adapter/main/init.rb?token=xxx...
            c.get(url)
            #=> "require 'redmine'\nrequire File.expand_path('../lib/github_repositories_helper_patch', __FILE__)\n\nRedmine::Plugin.register :redmine_github_adapter do\n  name 'Redmine Github Adapter plugin'\n  author '\Author name'\n  description 'This is a plugin for Redmine'\n  version '0.0.1'\n  url 'http://example.com/path/to/plugin'\n  author_url 'http://example.com/about'\n  Redmine::Scm::Base.add \"Github\"\nend\n"
            content_type = c.last_response.headers['content-type']
            #=> "text/plain; charset=utf-8"
            content_type.slice(/charset=.+$/).gsub("charset=", "") == "binary"
          end
        end

      end
    end
  end
end
