class CreateTopicSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :topic_subscriptions do |t|
      t.references :user, null: false, foreign_key: { on_delete: :cascade }
      t.references :topic, null: false, foreign_key: { on_delete: :cascade }
      t.string :discord_webhook
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :topic_subscriptions, [ :user_id, :topic_id ], unique: true
  end
end
