# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_04_27_143440) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "push_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.string "endpoint", null: false
    t.string "p256dh_key", null: false
    t.string "auth_key", null: false
    t.string "user_agent"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["user_id", "endpoint"], name: "index_push_subscriptions_on_user_id_and_endpoint", unique: true
    t.index ["user_id"], name: "index_push_subscriptions_on_user_id"
  end

  create_table "stories", force: :cascade do |t|
    t.bigint "hn_id", null: false
    t.string "title"
    t.string "url"
    t.string "by"
    t.integer "score", default: 0, null: false
    t.integer "descendants", default: 0, null: false
    t.string "story_type"
    t.text "text"
    t.datetime "hn_created_at"
    t.datetime "first_seen_at"
    t.datetime "last_polled_at"
    t.string "tracking_status", default: "active", null: false
    t.datetime "archived_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["hn_id"], name: "index_stories_on_hn_id", unique: true
    t.index ["last_polled_at"], name: "index_stories_on_last_polled_at"
    t.index ["tracking_status"], name: "index_stories_on_active", where: "((tracking_status)::text = 'active'::text)"
  end

  create_table "story_snapshots", force: :cascade do |t|
    t.bigint "story_id", null: false
    t.integer "score", null: false
    t.integer "descendants", default: 0, null: false
    t.datetime "captured_at", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["story_id", "captured_at"], name: "index_story_snapshots_on_story_id_and_captured_at"
    t.index ["story_id"], name: "index_story_snapshots_on_story_id"
  end

  create_table "topic_subscriptions", force: :cascade do |t|
    t.bigint "user_id", null: false
    t.bigint "topic_id", null: false
    t.string "discord_webhook"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["topic_id"], name: "index_topic_subscriptions_on_topic_id"
    t.index ["user_id", "topic_id"], name: "index_topic_subscriptions_on_user_id_and_topic_id", unique: true
    t.index ["user_id"], name: "index_topic_subscriptions_on_user_id"
  end

  create_table "topics", force: :cascade do |t|
    t.bigint "created_by_id"
    t.string "name", null: false
    t.text "keywords", default: [], null: false, array: true
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((name)::text)", name: "index_topics_on_lower_name", unique: true
    t.index ["created_by_id"], name: "index_topics_on_created_by_id"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "admin", default: false, null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  add_foreign_key "push_subscriptions", "users"
  add_foreign_key "story_snapshots", "stories"
  add_foreign_key "topic_subscriptions", "topics", on_delete: :cascade
  add_foreign_key "topic_subscriptions", "users", on_delete: :cascade
  add_foreign_key "topics", "users", column: "created_by_id", on_delete: :nullify
end
