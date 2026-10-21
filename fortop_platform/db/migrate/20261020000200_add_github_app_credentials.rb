class AddGithubAppCredentials < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :github_refresh_token, :text
    add_column :users, :github_token_expires_at, :datetime
    add_column :repositories, :installation_id, :bigint
    add_index :repositories, :installation_id
  end
end
