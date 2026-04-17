# Task 3 — Install and configure Devise

**Status:** pending
**Depends on:** Task 2.

## Files

- Create: `config/initializers/devise.rb` (generator), `app/models/user.rb`, `db/migrate/*_devise_create_users.rb`, `spec/factories/users.rb`
- Modify: `config/environments/development.rb`

## Steps

1. `bin/rails generate devise:install`

2. Add to `config/environments/development.rb` inside the `config` block:
   ```ruby
   config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
   ```

3. Generate User model and migrate:
   ```bash
   bin/rails generate devise User
   bin/rails db:migrate
   ```

4. Generate Devise views (kept as plain ERB on purpose, not Inertia):
   ```bash
   bin/rails generate devise:views
   ```

5. Create `spec/factories/users.rb`:
   ```ruby
   FactoryBot.define do
     factory :user do
       sequence(:email) { |n| "user#{n}@example.com" }
       password { "password123" }
       password_confirmation { "password123" }
     end
   end
   ```

6. Manual smoke (optional): `bin/rails server` → visit `/users/sign_up`, create a user. A "no route matches '/'" error after signup is OK — root isn't defined until Task 6.

7. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: add devise user model and auth views"
   ```
