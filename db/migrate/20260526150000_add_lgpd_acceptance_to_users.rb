class AddLgpdAcceptanceToUsers < ActiveRecord::Migration[7.1]
  def change
    add_column :users, :accepted_terms_version, :string
    add_column :users, :accepted_privacy_version, :string
    add_column :users, :accepted_at, :datetime
    add_index :users, :accepted_terms_version
  end
end
