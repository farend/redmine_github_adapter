class CreateGithubAdapterRootFilesets < ActiveRecord::Migration[4.2]
  def change
    create_table :github_adapter_root_filesets do |t|
      t.integer :repository_id, :null => false
      t.string  :revision, :null => false
      t.integer :changeset_id, :null => false
      t.string  :path, :null => false
      t.string  :size, :null => true
      t.string  :latest_commitid, :null => false
    end
  end
end
