require 'redmine/scm/adapters/abstract_adapter'

module Redmine
  module Scm
    module Adapters
      class GithubAdapter < AbstractAdapter
        GIT_DEFAULT_BRANCH_NAMES = %w[main master].freeze
        class GithubBranch < Branch
          attr_accessor :is_default
        end

        PER_PAGE = 100
        MAX_PAGES = 10

        def initialize(url, root_url=nil, login=nil, password=nil, path_encoding=nil)
          super

          ## Set Github endpoint and token
          @repos = url.gsub("https://github.com/", '').gsub(/\/$/, '').gsub(/.git$/, '')
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

        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def entries(path=nil, identifier=nil, options={})
          identifier = 'HEAD' if identifier.nil?

          entries = Entries.new

          files = Array.wrap(Octokit.contents(@repos, path: path, ref: identifier))

          if files.length > 0
            files.each do |file|
              full_path = file.path
              next if entries.find{|entry| entry.name == full_path}
              entries << Entry.new({
                :name => file.name.dup,
                :path => file.path.dup,
                :kind => file.type,
                :size => (file.type == "dir") ? nil : file.size,
                :lastrev => options[:report_last_commit] ? lastrev(full_path, identifier) : Revision.new
              })
            end
          end
          entries.sort_by_name

        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def revision_to_sha(rev)
          Octokit.commits(@repos, rev, { per_page: 1 }).map(&:sha).first
        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def lastrev(path, rev)
          return if path.nil?

          github_commits = Octokit.commits(@repos, rev, { path: path, per_page: 1 })
          return if github_commits.blank?

          github_commit = github_commits.first
          return Revision.new({
            :identifier => github_commit.sha,
            :scmid      => github_commit.sha,
            :author     => github_commit.commit.author.name,
            :time       => github_commit.commit.committer.date,
            :message    => nil,
            :paths      => nil
          })
        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def get_path_name(path)

          Octokit.commits(@repos).map {|c|
            Octokit.tree(@repos, c.commit.tree.sha).tree.map{|b| [b.sha, b.path] }
          }.flatten.each_slice(2).to_h[path]

        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def revisions(path, identifier_from, identifier_to, options={})
          path ||= ''
          revs = Revisions.new
          per_page = options[:limit] ? options[:limit].to_i : PER_PAGE

          api_opts = { all: true, path: path, per_page: per_page }
          api_opts[:since] = options[:last_committed_date] if options[:last_committed_date]

          if options[:all]
            ## STEP 1: Seek start_page
            start_page = 1
            0.step do |i|
              start_page = i * MAX_PAGES + 1
              github_commits = Octokit.commits(@repos, api_opts.merge(page: start_page))

              # if fetched latest commit, github_commits.length is 1, and github_commits[0][:sha] == latest_committed_id
              return [] if i == 0 && github_commits.none?{ |commit| commit.sha != options[:last_committed_id] }

              break if github_commits.length < per_page
            end

            # if found end of page, Go back MAX_PAGES from end of page.
            start_page = start_page - MAX_PAGES if start_page > MAX_PAGES

            ## Step 2: Get the commits from start_page
            start_page.step do |i|
              github_commits = Octokit.commits(@repos, api_opts.merge(page: i))
              break if github_commits.length == 0
              github_commits.each do |github_commit|
                revision = Revision.new({
                  :identifier => github_commit.sha,
                  :scmid      => github_commit.sha,
                  :author     => github_commit.commit.author.name,
                  :time       => github_commit.commit.committer.date,
                  :message    => github_commit.commit.message,
                  :paths      => nil, # Set paths later (In "get_filechanges_and_append_to" method.)
                  :parents    => github_commit.parents.map(&:sha)
                })
                revs << revision
              end
            end
          else
            github_commits = Octokit.commits(@repos, identifier_to, { path: path, per_page: per_page })
            github_commits.each do |github_commit|
              revision = Revision.new({
                :identifier => github_commit.sha,
                :scmid      => github_commit.sha,
                :author     => github_commit.commit.author.name,
                :time       => github_commit.commit.committer.date,
                :message    => github_commit.commit.message,
                :paths      => [],
                :parents    => github_commit.parents.map(&:sha)
              })
              revs << revision
            end
          end

          revs.reverse.sort{ |a, b| a.time <=> b.time }

        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def get_filechanges_and_append_to(revisions)
          revisions.each do |revision|
            commit_diff = Octokit.commit(@repos, revision.identifier)
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
            end
            revision.paths = files
          end
        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def diff(path, identifier_from, identifier_to=nil)
          path ||= ''
          diff = []

          if identifier_to.nil?
            github_diffs = Octokit.commit(@repos, identifier_from, path: path).files
          else
            github_diffs = Octokit.compare(@repos, identifier_to, identifier_from, path: path).files
          end

          github_diffs.each do |github_diff|
            if path.length > 0
              next if github_diff.filename != path && !github_diff.filename.include?("#{path}/")
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
              cat(github_diff.filename, identifier_to).split("\n").each do |line|
                diff << "+#{line}"
              end
            when "removed"
              diff << "diff"
              diff << "--- a/#{github_diff.filename}"
              diff << "+++ /dev/null"
              diff << "@@ -1,2 +0,0 @@"
              cat(github_diff.filename, identifier_from).split("\n").each do |line|
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

        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
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
          identifier ||= 'HEAD'
          if path.blank?
            # Root entry
            Entry.new(:path => '', :kind => 'dir')
          else
            es = entries(path, identifier, {report_last_commit: true })
            content = es&.find {|e| e.name == path} || es&.first

            Entry.new({
              :name => content&.name,
              :path => content&.path,
              :kind => content&.path&.include?("#{path}/") ? 'dir' : content&.kind,
              :size => (content&.kind == "dir") ? nil : content&.size,
            })
          end
        end

        def cat(path, identifier=nil)
          identifier = 'HEAD' if identifier.nil?

          begin
            blob = Octokit.contents(@repos, path: path, ref: identifier)
            url = blob.download_url
          rescue Octokit::NotFound
            commit = Octokit.commit(@repos, identifier).files.select{|c| c.filename == path }.first
            blob = Octokit.blob(@repos, commit.sha)
            url = commit.raw_url
          end
          Octokit.get(url)
          content_type = Octokit.last_response.headers['content-type'].slice(/charset=.+$/)&.gsub("charset=", "")
          return '' if content_type == "binary" || content_type.nil?

          content = blob.encoding == "base64" ? Base64.decode64(blob.content) : blob.content
          content.force_encoding 'utf-8'

        rescue Octokit::Error => e
          raise CommandFailed, handle_octokit_error(e)
        end

        def valid_name?(name)
          true
        end

        def handle_octokit_error(e)
          logger.error "scm: github: error: #{e.message}"
          gh_error = JSON.parse(e.response_body.to_s)['message'].presence
          gh_error ? 'error response from GitHub: ' + gh_error : ''
        end

      end # end GitHubAdapter
    end # end Adapters
  end # end Scm
end # end Redmine
