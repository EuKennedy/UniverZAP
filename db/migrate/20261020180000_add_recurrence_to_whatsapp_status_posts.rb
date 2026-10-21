class AddRecurrenceToWhatsappStatusPosts < ActiveRecord::Migration[7.1]
  def change
    add_column :whatsapp_status_posts, :recurrence, :string, null: false, default: 'none'
  end
end
