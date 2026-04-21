# Task 16 — Seed data for manual verification

**Status:** pending
**Depends on:** Task 15 (independent from Task 15 — run either order).

Seeds an admin user, a regular user, a few sample topics, and one subscription so the dashboard has something to show on first boot.

## Files

- Modify: `db/seeds.rb`

## Steps

1. Edit `db/seeds.rb`:
   ```ruby
   if Rails.env.development?
     admin = User.find_or_create_by!(email: "admin@example.com") do |u|
       u.password = "password123"
       u.password_confirmation = "password123"
     end
     admin.update!(admin: true) unless admin.admin?

     user = User.find_or_create_by!(email: "dev@example.com") do |u|
       u.password = "password123"
       u.password_confirmation = "password123"
     end

     ai = Topic.find_or_create_by!(name: "AI agents") do |t|
       t.keywords = ["AI agent", "LLM agent", "agentic", "autonomous agent"]
       t.active = true
       t.created_by = admin
     end

     Topic.find_or_create_by!(name: "Rust") do |t|
       t.keywords = ["rust lang", "rustlang", "cargo"]
       t.active = true
       t.created_by = admin
     end

     TopicSubscription.find_or_create_by!(user: user, topic: ai) do |s|
       s.active = true
       s.discord_webhook = nil
     end

     puts "Seeded admin:     admin@example.com / password123 (admin)"
     puts "Seeded user:      dev@example.com   / password123 (subscribed to 'AI agents')"
   end
   ```

2. Run seeds and verify manually:
   ```bash
   bin/rails db:seed
   bin/rails server
   # Visit http://localhost:3000/users/sign_in
   # Log in as admin@example.com → dashboard loads; /admin/topics shows the catalog.
   # Sign out, log in as dev@example.com → /topics shows both, "AI agents" is subscribed.
   ```
   Stop the server.

3. **Commit.**
   ```bash
   git add -A
   git commit -m "chore: seed admin + regular user + sample topics and a subscription"
   ```
