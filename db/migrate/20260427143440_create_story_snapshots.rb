class CreateStorySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :story_snapshots do |t|
      t.references :story, null: false, foreign_key: true
      t.integer :score, null: false
      t.integer :descendants, null: false, default: 0
      t.datetime :captured_at, null: false
      t.timestamps
    end
    add_index :story_snapshots, [ :story_id, :captured_at ]
  end
end
