class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :match, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :sent_at
      t.text :error
      t.timestamps
    end
    add_index :notifications,
              [ :match_id, :channel, :target_type, :target_id ],
              unique: true,
              name: "index_notifications_on_match_channel_target"
  end
end
