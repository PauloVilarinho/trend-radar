class CreateMatches < ActiveRecord::Migration[8.0]
  def change
    create_table :matches do |t|
      t.references :story, null: false, foreign_key: true
      t.references :topic, null: false, foreign_key: true
      t.decimal :relevance_score, precision: 4, scale: 3
      t.text :reason
      t.decimal :velocity_score, precision: 8, scale: 2
      t.datetime :matched_at, null: false
      t.datetime :dismissed_at
      t.datetime :posted_at
      t.timestamps
    end
    add_index :matches, [ :story_id, :topic_id ], unique: true
    add_index :matches, [ :topic_id, :matched_at ]
  end
end
