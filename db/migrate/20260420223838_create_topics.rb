class CreateTopics < ActiveRecord::Migration[8.0]
  def change
    create_table :topics do |t|
      t.references :created_by,
                   foreign_key: { to_table: :users, on_delete: :nullify },
                   null: true
      t.string :name, null: false
      t.text :keywords, array: true, null: false, default: []
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :topics, "LOWER(name)", unique: true, name: "index_topics_on_lower_name"
  end
end
