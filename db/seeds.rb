# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).

admin = User.find_or_create_by!(email: "admin@example.com") do |u|
  u.password = "password123"
  u.password_confirmation = "password123"
  u.admin = true
end
admin.update!(admin: true) unless admin.admin?

User.find_or_create_by!(email: "user@example.com") do |u|
  u.password = "password123"
  u.password_confirmation = "password123"
end

[
  { name: "AI agents", keywords: %w[agent agents llm autonomous] },
  { name: "Rust", keywords: %w[rust cargo] },
  { name: "Databases", keywords: [ "postgres", "sqlite", "database" ] }
].each do |attrs|
  Topic.find_or_create_by!(name: attrs[:name]) do |t|
    t.keywords = attrs[:keywords]
    t.created_by = admin
  end
end

Rails.logger.info "Seeded: admin@example.com (admin), user@example.com, 3 topics"
