class AddIndexOnGithubAdapterRootFilesets < ActiveRecord::Migration[4.2]
  def change
    add_index :github_adapter_root_filesets, [:repository_id, :changeset_id],
      name: 'index_github_adapter_root_filesets_on_repo_id_and_chst_id'
  end
end
