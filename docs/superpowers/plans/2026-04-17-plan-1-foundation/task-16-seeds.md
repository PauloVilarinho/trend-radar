# Task 16 — Seed data for manual verification

**Status:** pending
**Depends on:** Task 15 (any order relative to Task 15 is fine — they're independent).

## Files

- Modify: `db/seeds.rb`

## Steps

1. Edit `db/seeds.rb`:
   ```ruby
   if Rails.env.development?
     user = User.find_or_create_by!(email: "dev@example.com") do |u|
       u.password = "password123"
       u.password_confirmation = "password123"
     end

     Topic.find_or_create_by!(user: user, name: "AI agents") do |t|
       t.keywords = ["AI agent", "LLM agent", "agentic", "autonomous agent"]
       t.active = true
     end

     Topic.find_or_create_by!(user: user, name: "Rust") do |t|
       t.keywords = ["rust lang", "rustlang", "cargo"]
       t.active = true
     end

     puts "Seed user: dev@example.com / password123"
   end
   ```

2. Run seeds and verify manually:
   ```bash
   bin/rails db:seed
   bin/rails server
   # Visit http://localhost:3000/users/sign_in
   # Log in as dev@example.com / password123
   # Dashboard loads; /topics shows "AI agents" and "Rust"
   ```
   Stop the server.

3. **Commit.**
   ```bash
   git add -A
   git commit -m "chore: add dev seed data (user + 2 sample topics)"
   ```
