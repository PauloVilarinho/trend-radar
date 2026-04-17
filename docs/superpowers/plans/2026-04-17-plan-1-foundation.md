# Trend Radar — Plan 1: Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bootstrap a Rails 8 + Inertia/React + Devise application with Topic and PushSubscription models, working CRUD UI for topics, Kamal deployment config, and CI. Produces a working web app where users can sign up and manage topic subscriptions — no data ingestion yet.

**Architecture:** Single Rails 8 monolith. Authentication via Devise with plain ERB views. Rest of app uses Inertia.js to render React pages from Rails controllers. PostgreSQL for data. SolidQueue for background jobs (used by later plans; configured here). Deploy via Kamal 2 to a single VPS.

**Tech Stack:** Ruby 3.3+, Rails 8.0+, PostgreSQL 16+, Devise, inertia_rails gem, React 18, Vite (vite_rails), TailwindCSS 3, RSpec, FactoryBot, WebMock, VCR, Kamal 2.

---

## File Structure

New files created in this plan:

| File | Purpose |
|---|---|
| `Gemfile`, `Gemfile.lock` | Ruby dependencies |
| `config/database.yml` | Postgres config |
| `config/routes.rb` | Route definitions |
| `config/initializers/devise.rb` | Devise config |
| `config/initializers/inertia_rails.rb` | Inertia SSR/version config |
| `config/deploy.yml` | Kamal deploy config |
| `app/frontend/entrypoints/application.tsx` | Vite entrypoint, Inertia bootstrap |
| `app/frontend/Layouts/AppLayout.tsx` | Shared React layout |
| `app/frontend/Pages/Dashboard/Index.tsx` | Dashboard placeholder |
| `app/frontend/Pages/Topics/Index.tsx` | Topics list page |
| `app/frontend/Pages/Topics/New.tsx` | Topic create form |
| `app/frontend/Pages/Topics/Edit.tsx` | Topic edit form |
| `app/models/user.rb` | Devise User |
| `app/models/topic.rb` | Topic with validations |
| `app/models/push_subscription.rb` | Push subscription record |
| `app/controllers/application_controller.rb` | Base controller with Inertia helpers |
| `app/controllers/dashboard_controller.rb` | Dashboard landing |
| `app/controllers/topics_controller.rb` | Topics CRUD |
| `db/migrate/*_devise_create_users.rb` | Users table |
| `db/migrate/*_create_topics.rb` | Topics table |
| `db/migrate/*_create_push_subscriptions.rb` | Push subscriptions table |
| `spec/rails_helper.rb`, `spec/spec_helper.rb` | RSpec config |
| `spec/factories/*.rb` | FactoryBot factories |
| `spec/models/topic_spec.rb` | Topic model tests |
| `spec/requests/topics_spec.rb` | Topics controller tests |
| `spec/support/inertia_helpers.rb` | Test helpers for Inertia |
| `.github/workflows/ci.yml` | CI pipeline |

---

## Task 1: Bootstrap Rails 8 application

**Files:**
- Create: full Rails app skeleton in project root

- [ ] **Step 1: Verify Ruby version**

Run: `ruby -v`
Expected: Ruby 3.3.0 or newer. If not, install via rbenv/asdf.

- [ ] **Step 2: Generate Rails 8 app**

Run from `/Users/paulotarso/codeminer42/trend-radar`:
```bash
gem install rails -v "~> 8.0.0"
rails new . --database=postgresql --css=tailwind --javascript=vite --skip-test --force
```

The `--force` overwrites the existing empty dir. `--skip-test` because we'll use RSpec.

- [ ] **Step 3: Verify app boots**

Run:
```bash
bin/rails db:create
bin/rails server
```
Expected: server starts on `localhost:3000`, default Rails welcome page loads. Stop with Ctrl-C.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: bootstrap Rails 8 app with postgres, tailwind, vite"
```

---

## Task 2: Add core gems (Devise, Inertia, RSpec, testing tools)

**Files:**
- Modify: `Gemfile`

- [ ] **Step 1: Add gems to Gemfile**

Append to `Gemfile`:
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

- [ ] **Step 2: Install**

Run: `bundle install`
Expected: bundle completes without errors.

- [ ] **Step 3: Initialize RSpec**

Run: `bin/rails generate rspec:install`
Expected: creates `spec/spec_helper.rb`, `spec/rails_helper.rb`, `.rspec`.

- [ ] **Step 4: Configure RSpec for FactoryBot, WebMock, VCR**

Edit `spec/rails_helper.rb`. After `require 'rspec/rails'` line, add:

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

Inside the `RSpec.configure` block, add:
```ruby
  config.include FactoryBot::Syntax::Methods
```

- [ ] **Step 5: Smoke-test RSpec**

Run: `bin/rspec`
Expected: "No examples found." with exit 0.

- [ ] **Step 6: Commit**

```bash
git add Gemfile Gemfile.lock .rspec spec/
git commit -m "chore: add devise, inertia, rspec, webmock, vcr, factory_bot"
```

---

## Task 3: Install and configure Devise

**Files:**
- Create: `config/initializers/devise.rb`
- Create: `app/models/user.rb`
- Create: `db/migrate/*_devise_create_users.rb`

- [ ] **Step 1: Run Devise generator**

```bash
bin/rails generate devise:install
```

- [ ] **Step 2: Configure default URL options**

Edit `config/environments/development.rb`. Add inside the `config` block:
```ruby
  config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

- [ ] **Step 3: Generate User model**

```bash
bin/rails generate devise User
bin/rails db:migrate
```

- [ ] **Step 4: Generate Devise views**

```bash
bin/rails generate devise:views
```

These are plain ERB views — intentionally not Inertia. They will render with a minimal layout.

- [ ] **Step 5: Write user factory**

Create `spec/factories/users.rb`:
```ruby
FactoryBot.define do
  factory :user do
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    password_confirmation { "password123" }
  end
end
```

- [ ] **Step 6: Verify sign-up works manually**

Run `bin/rails server`, visit `http://localhost:3000/users/sign_up`, create a user. Expected: redirect to `/` (root not yet defined — will be added in Task 6; a "no route matches" error is acceptable here). Stop server.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add devise user model and auth views"
```

---

## Task 4: Install and configure Inertia.js + React

**Files:**
- Create: `app/frontend/entrypoints/application.tsx`
- Create: `app/frontend/Layouts/AppLayout.tsx`
- Create: `app/views/layouts/application.html.erb` (modify to host Inertia root)
- Create: `config/initializers/inertia_rails.rb`

- [ ] **Step 1: Install inertia-rails generator + React dependencies**

```bash
bin/rails generate inertia:install --framework=react --typescript --vite
```

This generator installs npm packages (@inertiajs/react, react, react-dom, typescript, @vitejs/plugin-react), configures `vite.config.ts`, and creates an initial `application.tsx`.

- [ ] **Step 2: Verify the generator's scaffolding**

Confirm these exist:
- `app/frontend/entrypoints/application.tsx`
- `app/frontend/pages/` (note lowercase — we'll rename to `Pages` for convention)
- `vite.config.ts` has React plugin configured
- `package.json` has `react`, `react-dom`, `@inertiajs/react`

- [ ] **Step 3: Rename `pages/` → `Pages/` and `layouts/` → `Layouts/`**

```bash
git mv app/frontend/pages app/frontend/Pages
mkdir -p app/frontend/Layouts
```

- [ ] **Step 4: Create shared layout**

Create `app/frontend/Layouts/AppLayout.tsx`:
```tsx
import { ReactNode } from "react";
import { Link, usePage } from "@inertiajs/react";

type PageProps = {
  current_user: { email: string } | null;
  flash: { notice?: string; alert?: string };
};

export default function AppLayout({ children }: { children: ReactNode }) {
  const { current_user, flash } = usePage<PageProps>().props;

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="mx-auto max-w-6xl px-4 py-3 flex justify-between items-center">
          <Link href="/" className="font-semibold text-lg">Trend Radar</Link>
          <nav className="flex gap-4 text-sm">
            {current_user ? (
              <>
                <Link href="/topics">Topics</Link>
                <Link href="/users/sign_out" method="delete" as="button">Sign out</Link>
              </>
            ) : (
              <>
                <Link href="/users/sign_in">Sign in</Link>
                <Link href="/users/sign_up">Sign up</Link>
              </>
            )}
          </nav>
        </div>
      </header>
      {flash.notice && (
        <div className="bg-green-50 text-green-800 px-4 py-2 text-sm">{flash.notice}</div>
      )}
      {flash.alert && (
        <div className="bg-red-50 text-red-800 px-4 py-2 text-sm">{flash.alert}</div>
      )}
      <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
    </div>
  );
}
```

- [ ] **Step 5: Wire AppLayout as default in entrypoint**

Edit `app/frontend/entrypoints/application.tsx` to use the layout by default. Replace the `resolve` function body with:
```tsx
import AppLayout from "../Layouts/AppLayout";

createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob("../Pages/**/*.tsx", { eager: true });
    const page = pages[`../Pages/${name}.tsx`] as { default: React.FC & { layout?: unknown } };
    page.default.layout ||= (page: React.ReactNode) => <AppLayout>{page}</AppLayout>;
    return page;
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />);
  },
});
```

(Imports for `createInertiaApp`, `createRoot`, `React` stay as generated.)

- [ ] **Step 6: Add shared Inertia props**

Create `app/controllers/application_controller.rb`, replacing generator content:
```ruby
class ApplicationController < ActionController::Base
  allow_browser versions: :modern
  before_action :authenticate_user!

  inertia_share do
    {
      current_user: current_user && { id: current_user.id, email: current_user.email },
      flash: { notice: flash[:notice], alert: flash[:alert] }.compact,
    }
  end
end
```

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: configure inertia + react with shared AppLayout"
```

---

## Task 5: Configure TailwindCSS for Inertia pages

**Files:**
- Modify: `app/frontend/entrypoints/application.css` (or create)
- Verify: `vite.config.ts` includes Tailwind

- [ ] **Step 1: Verify Tailwind is already wired**

Check `app/assets/tailwind/application.css` exists (from `--css=tailwind`). Check `app/views/layouts/application.html.erb` has `<%= stylesheet_link_tag "tailwind", "inter-font", "data-turbo-track": "reload" %>`.

- [ ] **Step 2: Ensure Tailwind scans React files**

Edit `config/tailwind.config.js` (or `tailwind.config.js`). In `content:`, add `./app/frontend/**/*.{js,jsx,ts,tsx}`:
```js
module.exports = {
  content: [
    "./public/*.html",
    "./app/helpers/**/*.rb",
    "./app/javascript/**/*.js",
    "./app/views/**/*.{erb,haml,html,slim}",
    "./app/frontend/**/*.{js,jsx,ts,tsx}",
  ],
  // ... rest unchanged
}
```

- [ ] **Step 3: Verify styling works**

Create a temporary test page: run `bin/rails server` + `bin/vite dev` (two terminals) and visit a page. Expected: Tailwind utility classes render correctly. Stop servers.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: configure tailwind to scan frontend/**"
```

---

## Task 6: Dashboard placeholder page + routes

**Files:**
- Create: `app/controllers/dashboard_controller.rb`
- Create: `app/frontend/Pages/Dashboard/Index.tsx`
- Modify: `config/routes.rb`

- [ ] **Step 1: Write failing request spec**

Create `spec/requests/dashboard_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  describe "GET /" do
    context "unauthenticated" do
      it "redirects to sign in" do
        get "/"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "authenticated" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "renders the dashboard inertia page" do
        get "/"
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Dashboard/Index")
      end
    end
  end
end
```

- [ ] **Step 2: Add Devise test helpers**

Edit `spec/rails_helper.rb`, add inside `RSpec.configure`:
```ruby
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include Devise::Test::IntegrationHelpers, type: :system
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `bin/rspec spec/requests/dashboard_spec.rb`
Expected: FAIL — no route for `/`.

- [ ] **Step 4: Add route, controller, page**

Edit `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  devise_for :users
  root to: "dashboard#index"
  get "up" => "rails/health#show", as: :rails_health_check
end
```

Create `app/controllers/dashboard_controller.rb`:
```ruby
class DashboardController < ApplicationController
  def index
    render inertia: "Dashboard/Index", props: {}
  end
end
```

Create `app/frontend/Pages/Dashboard/Index.tsx`:
```tsx
import { Head } from "@inertiajs/react";

export default function Index() {
  return (
    <>
      <Head title="Dashboard" />
      <h1 className="text-2xl font-semibold">Dashboard</h1>
      <p className="mt-2 text-gray-600">Matches will appear here once topics are set up.</p>
    </>
  );
}
```

- [ ] **Step 5: Run test — expect PASS**

Run: `bin/rspec spec/requests/dashboard_spec.rb`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add dashboard placeholder page at root"
```

---

## Task 7: Topic model with validations (TDD)

**Files:**
- Create: `db/migrate/*_create_topics.rb`
- Create: `app/models/topic.rb`
- Create: `spec/models/topic_spec.rb`
- Create: `spec/factories/topics.rb`

- [ ] **Step 1: Write failing model spec**

Create `spec/models/topic_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Topic, type: :model do
  describe "validations" do
    let(:user) { create(:user) }

    it "is valid with minimum required attributes" do
      topic = build(:topic, user: user)
      expect(topic).to be_valid
    end

    it "requires a name" do
      topic = build(:topic, name: nil)
      expect(topic).not_to be_valid
      expect(topic.errors[:name]).to be_present
    end

    it "requires a unique name per user" do
      existing = create(:topic, user: user, name: "AI")
      duplicate = build(:topic, user: user, name: "AI")
      expect(duplicate).not_to be_valid
    end

    it "allows same name for different users" do
      user2 = create(:user)
      create(:topic, user: user, name: "AI")
      other = build(:topic, user: user2, name: "AI")
      expect(other).to be_valid
    end

    it "requires at least one keyword" do
      topic = build(:topic, user: user, keywords: [])
      expect(topic).not_to be_valid
      expect(topic.errors[:keywords]).to be_present
    end

    it "rejects more than 20 keywords" do
      topic = build(:topic, user: user, keywords: Array.new(21) { |i| "kw#{i}" })
      expect(topic).not_to be_valid
      expect(topic.errors[:keywords]).to include(/too many/i)
    end

    it "rejects blank keyword strings" do
      topic = build(:topic, user: user, keywords: ["valid", "", "  "])
      expect(topic).not_to be_valid
    end

    it "validates discord_webhook format when present" do
      topic = build(:topic, user: user, discord_webhook: "https://example.com/webhook")
      expect(topic).not_to be_valid
      expect(topic.errors[:discord_webhook]).to be_present
    end

    it "accepts valid discord webhook URLs" do
      topic = build(:topic, user: user, discord_webhook: "https://discord.com/api/webhooks/123/abc")
      expect(topic).to be_valid
    end

    it "allows nil discord_webhook" do
      topic = build(:topic, user: user, discord_webhook: nil)
      expect(topic).to be_valid
    end
  end

  describe "user topic limit" do
    let(:user) { create(:user) }

    it "rejects creating a 51st topic for a user" do
      50.times { |i| create(:topic, user: user, name: "topic#{i}") }
      over = build(:topic, user: user, name: "too_many")
      expect(over).not_to be_valid
      expect(over.errors[:base]).to include(/limit/i)
    end
  end
end
```

- [ ] **Step 2: Create topic factory**

Create `spec/factories/topics.rb`:
```ruby
FactoryBot.define do
  factory :topic do
    user
    sequence(:name) { |n| "Topic #{n}" }
    keywords { ["AI", "machine learning"] }
    discord_webhook { nil }
    active { true }
  end
end
```

- [ ] **Step 3: Run tests — expect FAIL**

Run: `bin/rspec spec/models/topic_spec.rb`
Expected: FAIL — `Topic` not defined.

- [ ] **Step 4: Generate migration and model**

```bash
bin/rails generate migration CreateTopics user:references name:string keywords:text discord_webhook:string active:boolean
```

Edit the generated migration:
```ruby
class CreateTopics < ActiveRecord::Migration[8.0]
  def change
    create_table :topics do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :keywords, array: true, null: false, default: []
      t.string :discord_webhook
      t.boolean :active, null: false, default: true
      t.timestamps
    end
    add_index :topics, [:user_id, :name], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 5: Implement model**

Create `app/models/topic.rb`:
```ruby
class Topic < ApplicationRecord
  belongs_to :user

  MAX_KEYWORDS = 20
  MAX_TOPICS_PER_USER = 50
  DISCORD_WEBHOOK_REGEX = %r{\Ahttps://(?:discord\.com|discordapp\.com)/api/webhooks/\d+/[\w-]+\z}

  validates :name, presence: true, uniqueness: { scope: :user_id }
  validates :keywords, presence: true
  validate :validate_keywords
  validate :validate_discord_webhook
  validate :validate_user_topic_limit, on: :create

  encrypts :discord_webhook if respond_to?(:encrypts)

  private

  def validate_keywords
    return unless keywords.is_a?(Array)

    if keywords.empty? || keywords.all? { |k| k.to_s.strip.empty? }
      errors.add(:keywords, "must have at least one non-blank entry")
    end

    if keywords.any? { |k| k.to_s.strip.empty? }
      errors.add(:keywords, "contains blank entries")
    end

    if keywords.length > MAX_KEYWORDS
      errors.add(:keywords, "too many (max #{MAX_KEYWORDS})")
    end
  end

  def validate_discord_webhook
    return if discord_webhook.blank?
    return if DISCORD_WEBHOOK_REGEX.match?(discord_webhook)

    errors.add(:discord_webhook, "must be a valid Discord webhook URL")
  end

  def validate_user_topic_limit
    return unless user

    if user.topics.count >= MAX_TOPICS_PER_USER
      errors.add(:base, "topic limit of #{MAX_TOPICS_PER_USER} reached")
    end
  end
end
```

Add `has_many :topics` to `User`:
Edit `app/models/user.rb`:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :topics, dependent: :destroy
end
```

- [ ] **Step 6: Set up Rails encryption key (needed for `encrypts`)**

Run:
```bash
bin/rails db:encryption:init
```
Copy the output into `config/credentials.yml.enc` via:
```bash
EDITOR=vim bin/rails credentials:edit
```
Paste the active_record_encryption block from step output, save, close.

- [ ] **Step 7: Run tests — expect PASS**

Run: `bin/rspec spec/models/topic_spec.rb`
Expected: all examples PASS.

- [ ] **Step 8: Commit**

```bash
git add -A
git commit -m "feat: add Topic model with validations and keyword array"
```

---

## Task 8: PushSubscription model (TDD)

**Files:**
- Create: `db/migrate/*_create_push_subscriptions.rb`
- Create: `app/models/push_subscription.rb`
- Create: `spec/models/push_subscription_spec.rb`
- Create: `spec/factories/push_subscriptions.rb`

- [ ] **Step 1: Write failing spec**

Create `spec/models/push_subscription_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe PushSubscription, type: :model do
  let(:user) { create(:user) }

  it "is valid with all required fields" do
    sub = build(:push_subscription, user: user)
    expect(sub).to be_valid
  end

  it "requires endpoint" do
    sub = build(:push_subscription, user: user, endpoint: nil)
    expect(sub).not_to be_valid
  end

  it "requires p256dh_key" do
    sub = build(:push_subscription, user: user, p256dh_key: nil)
    expect(sub).not_to be_valid
  end

  it "requires auth_key" do
    sub = build(:push_subscription, user: user, auth_key: nil)
    expect(sub).not_to be_valid
  end

  it "rejects duplicate endpoints for same user" do
    existing = create(:push_subscription, user: user, endpoint: "https://push.example/abc")
    dup = build(:push_subscription, user: user, endpoint: "https://push.example/abc")
    expect(dup).not_to be_valid
  end
end
```

- [ ] **Step 2: Create factory**

Create `spec/factories/push_subscriptions.rb`:
```ruby
FactoryBot.define do
  factory :push_subscription do
    user
    sequence(:endpoint) { |n| "https://push.example.com/#{n}" }
    p256dh_key { "sample-p256dh-key" }
    auth_key { "sample-auth-key" }
    user_agent { "Mozilla/5.0" }
  end
end
```

- [ ] **Step 3: Run test — expect FAIL**

Run: `bin/rspec spec/models/push_subscription_spec.rb`
Expected: FAIL — class not defined.

- [ ] **Step 4: Migration**

```bash
bin/rails generate migration CreatePushSubscriptions user:references endpoint:string p256dh_key:string auth_key:string user_agent:string
```

Edit migration:
```ruby
class CreatePushSubscriptions < ActiveRecord::Migration[8.0]
  def change
    create_table :push_subscriptions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :endpoint, null: false
      t.string :p256dh_key, null: false
      t.string :auth_key, null: false
      t.string :user_agent
      t.timestamps
    end
    add_index :push_subscriptions, [:user_id, :endpoint], unique: true
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 5: Model**

Create `app/models/push_subscription.rb`:
```ruby
class PushSubscription < ApplicationRecord
  belongs_to :user

  validates :endpoint, presence: true,
                       uniqueness: { scope: :user_id }
  validates :p256dh_key, :auth_key, presence: true
end
```

Add `has_many :push_subscriptions, dependent: :destroy` to `User`:
```ruby
class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable
  has_many :topics, dependent: :destroy
  has_many :push_subscriptions, dependent: :destroy
end
```

- [ ] **Step 6: Run tests — expect PASS**

Run: `bin/rspec spec/models/push_subscription_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add PushSubscription model"
```

---

## Task 9: Topics index page (list user's topics)

**Files:**
- Modify: `config/routes.rb`
- Create: `app/controllers/topics_controller.rb`
- Create: `app/frontend/Pages/Topics/Index.tsx`
- Create: `spec/requests/topics_spec.rb`

- [ ] **Step 1: Write failing request spec**

Create `spec/requests/topics_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Topics", type: :request do
  let(:user) { create(:user) }

  describe "GET /topics" do
    context "unauthenticated" do
      it "redirects to sign in" do
        get "/topics"
        expect(response).to redirect_to(new_user_session_path)
      end
    end

    context "authenticated" do
      before { sign_in user }

      it "renders the topics index with user's topics only" do
        own = create(:topic, user: user, name: "Mine")
        create(:topic, name: "NotMine")

        get "/topics"

        expect(response).to have_http_status(:ok)
        expect(response.body).to include("Topics/Index")
        expect(response.body).to include("Mine")
        expect(response.body).not_to include("NotMine")
      end
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: FAIL — no route.

- [ ] **Step 3: Route**

Edit `config/routes.rb`:
```ruby
Rails.application.routes.draw do
  devise_for :users
  root to: "dashboard#index"
  resources :topics
  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [ ] **Step 4: Controller (index only for now)**

Create `app/controllers/topics_controller.rb`:
```ruby
class TopicsController < ApplicationController
  def index
    topics = current_user.topics.order(created_at: :desc)
    render inertia: "Topics/Index", props: {
      topics: topics.map { |t| topic_props(t) }
    }
  end

  private

  def topic_props(topic)
    {
      id: topic.id,
      name: topic.name,
      keywords: topic.keywords,
      active: topic.active,
      has_discord: topic.discord_webhook.present?,
    }
  end
end
```

- [ ] **Step 5: Page**

Create `app/frontend/Pages/Topics/Index.tsx`:
```tsx
import { Head, Link } from "@inertiajs/react";

type Topic = {
  id: number;
  name: string;
  keywords: string[];
  active: boolean;
  has_discord: boolean;
};

export default function Index({ topics }: { topics: Topic[] }) {
  return (
    <>
      <Head title="Topics" />
      <div className="flex justify-between items-center mb-4">
        <h1 className="text-2xl font-semibold">Topics</h1>
        <Link
          href="/topics/new"
          className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
        >
          New topic
        </Link>
      </div>
      {topics.length === 0 ? (
        <p className="text-gray-600">No topics yet. Create one to start monitoring.</p>
      ) : (
        <ul className="bg-white rounded border border-gray-200 divide-y">
          {topics.map((t) => (
            <li key={t.id} className="p-3 flex justify-between items-center">
              <div>
                <div className="font-medium">{t.name}</div>
                <div className="text-xs text-gray-500">
                  {t.keywords.join(", ")}
                  {t.has_discord && " · Discord"}
                  {!t.active && " · paused"}
                </div>
              </div>
              <Link href={`/topics/${t.id}/edit`} className="text-blue-600 text-sm">Edit</Link>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
```

- [ ] **Step 6: Run test — expect PASS**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add topics index page"
```

---

## Task 10: Topic create flow (new + create)

**Files:**
- Modify: `app/controllers/topics_controller.rb`
- Create: `app/frontend/Pages/Topics/New.tsx`
- Modify: `spec/requests/topics_spec.rb`

- [ ] **Step 1: Append failing specs for new/create**

Append to `spec/requests/topics_spec.rb`, inside the main describe:
```ruby
  describe "GET /topics/new" do
    before { sign_in user }

    it "renders the new topic form" do
      get "/topics/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Topics/New")
    end
  end

  describe "POST /topics" do
    before { sign_in user }

    context "with valid params" do
      it "creates a topic and redirects to index" do
        expect {
          post "/topics", params: {
            topic: { name: "Rust", keywords: ["rust lang", "cargo"], discord_webhook: "" }
          }
        }.to change(Topic, :count).by(1)
        expect(response).to redirect_to(topics_path)
      end
    end

    context "with invalid params" do
      it "renders new with errors" do
        post "/topics", params: { topic: { name: "", keywords: [] } }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("Topics/New")
      end
    end
  end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: specs for new/create fail.

- [ ] **Step 3: Extend controller**

Edit `app/controllers/topics_controller.rb`:
```ruby
class TopicsController < ApplicationController
  before_action :set_topic, only: [:edit, :update, :destroy]

  def index
    topics = current_user.topics.order(created_at: :desc)
    render inertia: "Topics/Index", props: {
      topics: topics.map { |t| topic_props(t) }
    }
  end

  def new
    render inertia: "Topics/New", props: {
      topic: empty_topic_form,
      errors: {},
    }
  end

  def create
    topic = current_user.topics.build(topic_params)
    if topic.save
      redirect_to topics_path, notice: "Topic created."
    else
      render inertia: "Topics/New", props: {
        topic: topic.attributes.slice("name", "keywords", "discord_webhook", "active"),
        errors: topic.errors.to_hash,
      }, status: :unprocessable_entity
    end
  end

  private

  def set_topic
    @topic = current_user.topics.find(params[:id])
  end

  def topic_params
    params.require(:topic).permit(:name, :discord_webhook, :active, keywords: [])
  end

  def topic_props(topic)
    {
      id: topic.id,
      name: topic.name,
      keywords: topic.keywords,
      active: topic.active,
      has_discord: topic.discord_webhook.present?,
    }
  end

  def empty_topic_form
    { name: "", keywords: [], discord_webhook: "", active: true }
  end
end
```

- [ ] **Step 4: Create New page**

Create `app/frontend/Pages/Topics/New.tsx`:
```tsx
import { Head, useForm } from "@inertiajs/react";
import { FormEvent } from "react";

type Form = { name: string; keywords: string[]; discord_webhook: string; active: boolean };
type Props = { topic: Form; errors: Record<string, string[]> };

export default function New({ topic, errors }: Props) {
  const form = useForm<Form>({
    name: topic.name,
    keywords: topic.keywords,
    discord_webhook: topic.discord_webhook,
    active: topic.active ?? true,
  });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    form.post("/topics");
  };

  const setKeywordsFromString = (s: string) => {
    form.setData("keywords", s.split(",").map((k) => k.trim()).filter(Boolean));
  };

  return (
    <>
      <Head title="New topic" />
      <h1 className="text-2xl font-semibold mb-4">New topic</h1>
      <form onSubmit={submit} className="max-w-lg space-y-4 bg-white p-4 rounded border">
        <Field label="Name" error={errors.name}>
          <input
            className="border rounded px-2 py-1 w-full"
            value={form.data.name}
            onChange={(e) => form.setData("name", e.target.value)}
          />
        </Field>
        <Field label="Keywords (comma-separated)" error={errors.keywords}>
          <input
            className="border rounded px-2 py-1 w-full"
            defaultValue={form.data.keywords.join(", ")}
            onBlur={(e) => setKeywordsFromString(e.target.value)}
          />
        </Field>
        <Field label="Discord webhook URL (optional)" error={errors.discord_webhook}>
          <input
            className="border rounded px-2 py-1 w-full"
            value={form.data.discord_webhook}
            onChange={(e) => form.setData("discord_webhook", e.target.value)}
          />
        </Field>
        <button
          type="submit"
          disabled={form.processing}
          className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm"
        >
          Create
        </button>
      </form>
    </>
  );
}

function Field({ label, error, children }: { label: string; error?: string[]; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="text-sm font-medium">{label}</span>
      <div className="mt-1">{children}</div>
      {error && <div className="text-red-600 text-xs mt-1">{error.join(", ")}</div>}
    </label>
  );
}
```

- [ ] **Step 5: Run tests — expect PASS**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add topic new/create flow"
```

---

## Task 11: Topic edit + update flow

**Files:**
- Modify: `app/controllers/topics_controller.rb`
- Create: `app/frontend/Pages/Topics/Edit.tsx`
- Modify: `spec/requests/topics_spec.rb`

- [ ] **Step 1: Append failing specs**

Append to `spec/requests/topics_spec.rb`:
```ruby
  describe "GET /topics/:id/edit" do
    let!(:topic) { create(:topic, user: user) }
    before { sign_in user }

    it "renders edit for own topic" do
      get "/topics/#{topic.id}/edit"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Topics/Edit")
    end

    it "404s for other user's topic" do
      other = create(:topic)
      expect { get "/topics/#{other.id}/edit" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "PATCH /topics/:id" do
    let!(:topic) { create(:topic, user: user, name: "Old") }
    before { sign_in user }

    it "updates valid params" do
      patch "/topics/#{topic.id}", params: { topic: { name: "New", keywords: ["a", "b"] } }
      expect(topic.reload.name).to eq("New")
      expect(response).to redirect_to(topics_path)
    end

    it "re-renders edit on invalid" do
      patch "/topics/#{topic.id}", params: { topic: { name: "", keywords: [] } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Topics/Edit")
    end
  end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: new specs fail.

- [ ] **Step 3: Extend controller**

Edit `app/controllers/topics_controller.rb`, add `edit` and `update` actions (place between `create` and `private`):
```ruby
  def edit
    render inertia: "Topics/Edit", props: {
      topic: full_topic_form(@topic),
      errors: {},
    }
  end

  def update
    if @topic.update(topic_params)
      redirect_to topics_path, notice: "Topic updated."
    else
      render inertia: "Topics/Edit", props: {
        topic: full_topic_form(@topic),
        errors: @topic.errors.to_hash,
      }, status: :unprocessable_entity
    end
  end
```

Add helper (in the private section):
```ruby
  def full_topic_form(topic)
    {
      id: topic.id,
      name: topic.name,
      keywords: topic.keywords,
      discord_webhook: topic.discord_webhook || "",
      active: topic.active,
    }
  end
```

- [ ] **Step 4: Create Edit page**

Create `app/frontend/Pages/Topics/Edit.tsx`:
```tsx
import { Head, useForm } from "@inertiajs/react";
import { FormEvent } from "react";

type Form = { id: number; name: string; keywords: string[]; discord_webhook: string; active: boolean };
type Props = { topic: Form; errors: Record<string, string[]> };

export default function Edit({ topic, errors }: Props) {
  const form = useForm<Omit<Form, "id">>({
    name: topic.name,
    keywords: topic.keywords,
    discord_webhook: topic.discord_webhook,
    active: topic.active,
  });

  const submit = (e: FormEvent) => {
    e.preventDefault();
    form.patch(`/topics/${topic.id}`);
  };

  const setKeywordsFromString = (s: string) => {
    form.setData("keywords", s.split(",").map((k) => k.trim()).filter(Boolean));
  };

  const destroy = () => {
    if (confirm("Delete this topic?")) {
      form.delete(`/topics/${topic.id}`);
    }
  };

  return (
    <>
      <Head title={`Edit: ${topic.name}`} />
      <h1 className="text-2xl font-semibold mb-4">Edit topic</h1>
      <form onSubmit={submit} className="max-w-lg space-y-4 bg-white p-4 rounded border">
        <Field label="Name" error={errors.name}>
          <input
            className="border rounded px-2 py-1 w-full"
            value={form.data.name}
            onChange={(e) => form.setData("name", e.target.value)}
          />
        </Field>
        <Field label="Keywords (comma-separated)" error={errors.keywords}>
          <input
            className="border rounded px-2 py-1 w-full"
            defaultValue={form.data.keywords.join(", ")}
            onBlur={(e) => setKeywordsFromString(e.target.value)}
          />
        </Field>
        <Field label="Discord webhook URL (optional)" error={errors.discord_webhook}>
          <input
            className="border rounded px-2 py-1 w-full"
            value={form.data.discord_webhook}
            onChange={(e) => form.setData("discord_webhook", e.target.value)}
          />
        </Field>
        <label className="flex items-center gap-2 text-sm">
          <input
            type="checkbox"
            checked={form.data.active}
            onChange={(e) => form.setData("active", e.target.checked)}
          />
          Active (receive notifications)
        </label>
        <div className="flex gap-2">
          <button type="submit" disabled={form.processing} className="bg-blue-600 text-white px-3 py-1.5 rounded text-sm">
            Save
          </button>
          <button type="button" onClick={destroy} className="bg-red-600 text-white px-3 py-1.5 rounded text-sm">
            Delete
          </button>
        </div>
      </form>
    </>
  );
}

function Field({ label, error, children }: { label: string; error?: string[]; children: React.ReactNode }) {
  return (
    <label className="block">
      <span className="text-sm font-medium">{label}</span>
      <div className="mt-1">{children}</div>
      {error && <div className="text-red-600 text-xs mt-1">{error.join(", ")}</div>}
    </label>
  );
}
```

- [ ] **Step 5: Run tests — expect PASS**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: all PASS.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add topic edit/update flow"
```

---

## Task 12: Topic destroy

**Files:**
- Modify: `app/controllers/topics_controller.rb`
- Modify: `spec/requests/topics_spec.rb`

- [ ] **Step 1: Append failing spec**

Append to `spec/requests/topics_spec.rb`:
```ruby
  describe "DELETE /topics/:id" do
    let!(:topic) { create(:topic, user: user) }
    before { sign_in user }

    it "deletes own topic" do
      expect {
        delete "/topics/#{topic.id}"
      }.to change(Topic, :count).by(-1)
      expect(response).to redirect_to(topics_path)
    end
  end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: fail — no destroy action.

- [ ] **Step 3: Add destroy action**

Edit `app/controllers/topics_controller.rb`, add between `update` and `private`:
```ruby
  def destroy
    @topic.destroy
    redirect_to topics_path, notice: "Topic deleted."
  end
```

- [ ] **Step 4: Run test — expect PASS**

Run: `bin/rspec spec/requests/topics_spec.rb`
Expected: all PASS.

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add topic destroy"
```

---

## Task 13: SolidQueue setup

**Files:**
- Modify: `config/database.yml`
- Create: `config/queue.yml`
- Modify: `config/application.rb`

- [ ] **Step 1: Install SolidQueue**

```bash
bin/rails solid_queue:install
bin/rails db:migrate
```

This generates `db/queue_schema.rb` and the queue database config.

- [ ] **Step 2: Verify queue connection**

Check `config/database.yml` has a `queue` entry (the installer adds it). Production config should include it too.

- [ ] **Step 3: Set Active Job adapter**

Edit `config/application.rb`, inside the `Application` class:
```ruby
    config.active_job.queue_adapter = :solid_queue
```

- [ ] **Step 4: Verify with a trivial job**

Run `bin/rails console`:
```ruby
class SmokeJob < ApplicationJob
  def perform; Rails.logger.info("smoke"); end
end
SmokeJob.perform_later
```
Then run: `bin/jobs start` (in another terminal, briefly) — expected: log shows "smoke". Stop with Ctrl-C. Remove SmokeJob from memory (exit console).

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "chore: install solid_queue for background jobs"
```

---

## Task 14: Kamal deployment config

**Files:**
- Modify: `config/deploy.yml`
- Create: `.kamal/secrets`

- [ ] **Step 1: Review generated Kamal config**

Rails 8 generates `config/deploy.yml`. Edit it for your VPS:
```yaml
service: trend-radar
image: trend-radar

servers:
  web:
    hosts:
      - <YOUR_VPS_IP>  # ← fill in with actual IP
  worker:
    hosts:
      - <YOUR_VPS_IP>
    cmd: bin/jobs start
  scheduler:
    hosts:
      - <YOUR_VPS_IP>
    cmd: bin/jobs start --recurring-schedule-file=config/recurring.yml

proxy:
  ssl: true
  host: <YOUR_DOMAIN>  # ← fill in

registry:
  server: ghcr.io
  username: <YOUR_GITHUB_USERNAME>
  password:
    - KAMAL_REGISTRY_PASSWORD

env:
  clear:
    RAILS_LOG_TO_STDOUT: "1"
    RAILS_SERVE_STATIC_FILES: "1"
  secret:
    - RAILS_MASTER_KEY
    - POSTGRES_PASSWORD
    - OPENAI_API_KEY
    - VAPID_PUBLIC_KEY
    - VAPID_PRIVATE_KEY
    - VAPID_SUBJECT

accessories:
  postgres:
    image: postgres:16
    host: <YOUR_VPS_IP>
    port: 5432
    env:
      clear:
        POSTGRES_USER: trend_radar
        POSTGRES_DB: trend_radar_production
      secret:
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
```

Note: the `<PLACEHOLDER>` values must be filled by the deployer before first deploy. This is expected configuration, not a plan placeholder.

- [ ] **Step 2: Create secrets file**

Create `.kamal/secrets`:
```
KAMAL_REGISTRY_PASSWORD=$(cat ~/.kamal/github_token)
RAILS_MASTER_KEY=$(cat config/master.key)
POSTGRES_PASSWORD=$KAMAL_POSTGRES_PASSWORD
OPENAI_API_KEY=$KAMAL_OPENAI_API_KEY
VAPID_PUBLIC_KEY=$KAMAL_VAPID_PUBLIC_KEY
VAPID_PRIVATE_KEY=$KAMAL_VAPID_PRIVATE_KEY
VAPID_SUBJECT=$KAMAL_VAPID_SUBJECT
```

Add to `.gitignore` (Kamal generator already does this):
```
.kamal/secrets
```

- [ ] **Step 3: Dockerfile sanity check**

Rails 8 generates a working `Dockerfile`. Verify it exists; build locally to confirm:
```bash
docker build -t trend-radar-test .
```
Expected: build succeeds. Delete image: `docker rmi trend-radar-test`.

- [ ] **Step 4: Commit**

```bash
git add -A
git commit -m "chore: configure kamal deployment for single-VPS setup"
```

---

## Task 15: CI pipeline

**Files:**
- Create: `.github/workflows/ci.yml`

- [ ] **Step 1: Create CI workflow**

Create `.github/workflows/ci.yml`:
```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: postgres
        ports: ["5432:5432"]
        options: >-
          --health-cmd pg_isready --health-interval 10s
          --health-timeout 5s --health-retries 5

    env:
      RAILS_ENV: test
      DATABASE_URL: postgres://postgres:postgres@localhost:5432
      OPENAI_API_KEY: dummy-for-vcr

    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: bin/rails db:create db:schema:load
      - run: bin/rspec
      - run: bin/vite build

  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: ruby/setup-ruby@v1
        with:
          bundler-cache: true
      - run: bundle exec rubocop || true  # soft-fail for MVP
```

- [ ] **Step 2: Commit**

```bash
git add -A
git commit -m "ci: add github actions workflow for rspec + vite build"
```

---

## Task 16: Seed data for manual verification

**Files:**
- Modify: `db/seeds.rb`

- [ ] **Step 1: Add dev seeds**

Edit `db/seeds.rb`:
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

- [ ] **Step 2: Run seeds and verify**

```bash
bin/rails db:seed
bin/rails server
# open http://localhost:3000/users/sign_in, log in as dev@example.com
# expected: dashboard loads, /topics shows 2 seeded topics
```

Stop the server.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "chore: add dev seed data (user + 2 sample topics)"
```

---

## Task 17: Integration smoke — full happy path (system test)

**Files:**
- Create: `spec/system/topic_management_spec.rb`

- [ ] **Step 1: Write system test**

Create `spec/system/topic_management_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Topic management", type: :system do
  before do
    driven_by(:rack_test)  # headless, no JS — sufficient for Inertia's initial page render
  end

  let(:user) { create(:user) }

  it "allows a user to create, edit, and delete a topic" do
    sign_in user

    visit "/topics"
    expect(page).to have_content("No topics yet")

    # Note: with rack_test we can't fully exercise Inertia client-side updates;
    # we hit the HTTP endpoints directly to verify the server side works end-to-end.
    page.driver.post "/topics", topic: { name: "AI", keywords: ["AI", "LLM"] }
    expect(Topic.count).to eq(1)

    visit "/topics"
    expect(page).to have_content("AI")

    topic = Topic.first
    page.driver.patch "/topics/#{topic.id}", topic: { name: "AI agents", keywords: ["AI", "LLM", "agent"] }
    expect(topic.reload.name).to eq("AI agents")

    page.driver.delete "/topics/#{topic.id}"
    expect(Topic.count).to eq(0)
  end
end
```

- [ ] **Step 2: Run — expect PASS**

Run: `bin/rspec spec/system/topic_management_spec.rb`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add -A
git commit -m "test: add system smoke test for topic management"
```

---

## Plan 1 Done — State of the Application

At the end of Plan 1 the app should:

- Boot locally (`bin/rails server` + `bin/vite dev`).
- Let a user sign up, log in, and sign out via Devise ERB views.
- Let a signed-in user view their topics list, create, edit, and delete topics.
- Reject invalid topic data with inline error messages.
- Have SolidQueue installed and ready (no jobs yet).
- Have a Kamal config ready to deploy (IP/domain fill-in required).
- Pass `bin/rspec` (all model, request, system tests green).
- Pass CI on GitHub Actions.

Plan 2 picks up from here and adds the HN ingestion pipeline and matching logic.
