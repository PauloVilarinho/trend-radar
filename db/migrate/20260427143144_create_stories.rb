class CreateStories < ActiveRecord::Migration[8.0]
  def change
    create_table :stories do |t|
      t.bigint :hn_id, null: false
      t.string :title
      t.string :url
      t.string :by
      t.integer :score, null: false, default: 0
      t.integer :descendants, null: false, default: 0
      t.string :story_type
      t.text :text
      t.datetime :hn_created_at
      t.datetime :first_seen_at
      t.datetime :last_polled_at
      t.string :tracking_status, null: false, default: "active"
      t.datetime :archived_at
      t.timestamps
    end
    add_index :stories, :hn_id, unique: true
    add_index :stories, :last_polled_at
    add_index :stories, :tracking_status, where: "tracking_status = 'active'",
              name: "index_stories_on_active"
  end
end
