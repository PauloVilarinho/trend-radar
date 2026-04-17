# Task 2 — Add core gems (Devise, Inertia, RSpec, testing tools)

**Status:** pending
**Depends on:** Task 1 (`05aa5d3`).

## Files

- Modify: `Gemfile`
- Create: `.rspec`, `spec/spec_helper.rb`, `spec/rails_helper.rb`

## Steps

1. **Append gems to `Gemfile`.** Append *outside* any existing group for non-grouped gems; for the grouped ones, append to the existing `:development, :test` and `:test` groups (don't duplicate group blocks).

   ```ruby
   gem "devise"
   gem "inertia_rails"
   gem "pg_search" # useful later; include now to avoid bundle churn

   group :development, :test do
     gem "rspec-rails", "~> 7.0"
     gem "factory_bot_rails"
     gem "faker"
     gem "dotenv-rails"
   end

   group :test do
     gem "webmock"
     gem "vcr"
     gem "capybara"
     gem "selenium-webdriver"
     gem "rails-controller-testing"
   end
   ```

2. **Install.** `bundle install` — expect clean finish.

3. **Initialize RSpec.** `bin/rails generate rspec:install` — creates `spec/spec_helper.rb`, `spec/rails_helper.rb`, `.rspec`.

4. **Configure RSpec.** Edit `spec/rails_helper.rb`.

   After `require 'rspec/rails'` add:
   ```ruby
   require "webmock/rspec"
   require "vcr"

   VCR.configure do |c|
     c.cassette_library_dir = "spec/fixtures/vcr_cassettes"
     c.hook_into :webmock
     c.configure_rspec_metadata!
     c.filter_sensitive_data("<OPENAI_API_KEY>") { ENV["OPENAI_API_KEY"] }
     c.default_cassette_options = { record: :new_episodes }
   end

   WebMock.disable_net_connect!(allow_localhost: true)
   ```

   Inside `RSpec.configure do |config|` add:
   ```ruby
     config.include FactoryBot::Syntax::Methods
   ```

5. **Smoke test.** `bin/rspec` → "No examples found." exit 0.

6. **Commit.**
   ```bash
   git add Gemfile Gemfile.lock .rspec spec/
   git commit -m "chore: add devise, inertia, rspec, webmock, vcr, factory_bot"
   ```
