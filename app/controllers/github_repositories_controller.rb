class GithubRepositoriesController < ApplicationController

  def fetch
    @repository = Repository.find(params[:id])

    head :bad_request unless @repository.is_a?(Repository::Github)

    before_info = @repository.extra_info&.dup

    @repository.fetch_changesets({ limit: 10 })

    after_info = @repository.extra_info

    if before_info&.fetch("last_committed_id") &&
      before_info&.fetch("last_committed_id") == after_info&.fetch("last_committed_id")
      render json: { status: 'OK' }
    else
      render json: { status: 'Processing' }
    end
  end
end
