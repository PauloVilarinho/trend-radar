# Trend Radar — Plan 2: Ingestion + Matching Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**2026-04-20 amendment:** topics are now a shared catalog, so classification is per (story, topic) rather than per (story, user, topic). `BackfillTopicJob` is renamed `BackfillSubscriptionJob` and fires on `TopicSubscription#create` (not `Topic#create`). Dashboard queries use `current_user.subscribed_topics` instead of `current_user.topics`.

**2026-04-27 amendment — persist all classifications:** `MatchJob` always inserts a `Match` row for every (story, topic) pair it classifies, even when the OpenAI relevance score is below threshold. This makes `Match.exists?(story_id:, topic_id:)` a complete idempotency record, so a story that re-triggers `MatchJob` after a velocity spike will skip pairs it already paid OpenAI for — including rejects. Behavioral implications: `Match.visible` now also filters by `relevance_score >= TrackingConfig.match[:min_relevance_score]`; `NotifyJob.perform_later` is only fired when the score clears the threshold; the Task 11 spec for "score below threshold" no longer asserts `not_to change(Match, :count)` — it asserts a Match is created but `NotifyJob` is not enqueued. Also: the daily-budget guard in `MatchJob#within_daily_budget?` uses strict `<` (not `<=`) so a configured budget of `0` correctly skips classification entirely.

**Goal:** Build the data pipeline that polls Hacker News, stores stories with time-series snapshots, detects climbing velocity, matches stories against the shared topic catalog via keyword prefilter + OpenAI classification, and surfaces matches on an in-app dashboard. At the end of this plan, a logged-in user subscribed to at least one topic sees matching climbing HN stories on the dashboard.

**Architecture:** Five job classes form the pipeline — `FetchFeedsJob` (every 5/30 min) → `FetchStoryJob` (per-item upsert + snapshot + archival + candidate decision) → `MatchJob` (keyword prefilter → OpenAI classification → match creation, scoped to ALL active topics — no user scoping). A `PruneSnapshotsJob` keeps the snapshots table bounded. `BackfillSubscriptionJob` seeds new subscribers against recent stories / existing matches. Dashboard is a new Inertia page with dismiss / mark-as-posted actions.

**Tech Stack:** Rails 8, PostgreSQL, SolidQueue (recurring schedules), Faraday (HTTP client for HN + OpenAI), `openai` gem or plain Faraday for OpenAI, RSpec + VCR + WebMock.

---

## File Structure

New files in this plan:

| File | Purpose |
|---|---|
| `db/migrate/*_create_stories.rb` | Stories table |
| `db/migrate/*_create_story_snapshots.rb` | Snapshots table |
| `db/migrate/*_create_matches.rb` | Matches table |
| `db/migrate/*_create_notifications.rb` | Notifications table (used in Plan 3, created here) |
| `app/models/story.rb` | Story model with archival |
| `app/models/story_snapshot.rb` | Snapshot model |
| `app/models/match.rb` | Match model |
| `app/models/notification.rb` | Notification model (skeleton) |
| `app/services/hn/client.rb` | HN HTTP client |
| `app/services/velocity_calculator.rb` | Pure function: snapshots → points/hour |
| `app/services/keyword_matcher.rb` | Topic keyword → story substring match |
| `app/services/openai/matcher.rb` | OpenAI classification call + JSON retry |
| `app/jobs/fetch_feeds_job.rb` | Entry poller |
| `app/jobs/fetch_story_job.rb` | Per-story upsert + snapshot + archive + candidate decision |
| `app/jobs/match_job.rb` | Topic prefilter + LLM + match creation |
| `app/jobs/prune_snapshots_job.rb` | Daily snapshot pruning |
| `app/jobs/backfill_subscription_job.rb` | Seed a new subscriber against recent stories / existing matches |
| `app/controllers/matches_controller.rb` | Dismiss + mark-as-posted actions |
| `app/frontend/pages/dashboard/index.tsx` | Updated: show matches |
| `config/tracking.yml` | Tunable thresholds |
| `config/recurring.yml` | SolidQueue recurring schedule |
| `spec/services/*` | Service specs |
| `spec/jobs/*` | Job specs |
| `spec/fixtures/vcr_cassettes/openai/*` | VCR cassettes |

---

## Task 1: Tracking configuration file

**Files:**
- Create: `config/tracking.yml`
- Create: `app/lib/tracking_config.rb`
- Create: `spec/lib/tracking_config_spec.rb`

- [ ] **Step 1: Write failing spec**

Create `spec/lib/tracking_config_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe TrackingConfig do
  it "loads velocity candidate threshold" do
    expect(TrackingConfig.velocity_candidate_threshold[:points_per_hour]).to eq(15)
    expect(TrackingConfig.velocity_candidate_threshold[:minimum_score]).to eq(30)
  end

  it "loads archival thresholds" do
    expect(TrackingConfig.archive[:hard_cutoff_hours]).to eq(72)
    expect(TrackingConfig.archive[:cooling_age_hours]).to eq(12)
    expect(TrackingConfig.archive[:cooling_points_per_hour]).to eq(3)
    expect(TrackingConfig.archive[:flat_snapshots_required]).to eq(3)
  end

  it "loads match thresholds" do
    expect(TrackingConfig.match[:min_relevance_score]).to eq(0.6)
    expect(TrackingConfig.match[:daily_classification_budget]).to eq(500)
  end

  it "loads snapshot retention" do
    expect(TrackingConfig.snapshot_retention_days).to eq(7)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/lib/tracking_config_spec.rb`
Expected: FAIL — `TrackingConfig` not defined.

- [ ] **Step 3: Create YAML**

Create `config/tracking.yml`:
```yaml
velocity_candidate_threshold:
  points_per_hour: 15
  minimum_score: 30
archive:
  hard_cutoff_hours: 72
  cooling_age_hours: 12
  cooling_points_per_hour: 3
  flat_snapshots_required: 3
match:
  min_relevance_score: 0.6
  daily_classification_budget: 500
snapshot_retention_days: 7
```

- [ ] **Step 4: Create loader**

Create `app/lib/tracking_config.rb`:
```ruby
module TrackingConfig
  extend self

  def velocity_candidate_threshold
    data.fetch(:velocity_candidate_threshold)
  end

  def archive
    data.fetch(:archive)
  end

  def match
    data.fetch(:match)
  end

  def snapshot_retention_days
    data.fetch(:snapshot_retention_days)
  end

  private

  def data
    @data ||= YAML.load_file(Rails.root.join("config/tracking.yml")).deep_symbolize_keys
  end
end
```

- [ ] **Step 5: Autoload check**

Ensure `app/lib` is autoloaded. Edit `config/application.rb`, inside `Application` class:
```ruby
    config.autoload_paths << Rails.root.join("app/lib")
    config.eager_load_paths << Rails.root.join("app/lib")
```

- [ ] **Step 6: Run — expect PASS**

Run: `bin/rspec spec/lib/tracking_config_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add tracking.yml config and loader"
```

---

## Task 2: Story model + migration

**Files:**
- Create: `db/migrate/*_create_stories.rb`
- Create: `app/models/story.rb`
- Create: `spec/factories/stories.rb`
- Create: `spec/models/story_spec.rb`

- [ ] **Step 1: Write failing model spec**

Create `spec/models/story_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Story, type: :model do
  describe "validations" do
    it "requires hn_id" do
      expect(build(:story, hn_id: nil)).not_to be_valid
    end

    it "enforces uniqueness on hn_id" do
      create(:story, hn_id: 999_999_999)
      expect(build(:story, hn_id: 999_999_999)).not_to be_valid
    end
  end

  describe "#age_hours" do
    it "returns hours since hn_created_at" do
      s = build(:story, hn_created_at: 6.hours.ago)
      expect(s.age_hours).to be_within(0.1).of(6.0)
    end
  end

  describe "#active?" do
    it "is true by default" do
      expect(build(:story).active?).to be true
    end

    it "is false when archived" do
      expect(build(:story, tracking_status: "archived").active?).to be false
    end
  end

  describe "#archive!" do
    it "sets status and timestamp" do
      story = create(:story)
      story.archive!
      expect(story.tracking_status).to eq("archived")
      expect(story.archived_at).to be_present
    end
  end
end
```

- [ ] **Step 2: Factory**

Create `spec/factories/stories.rb`:
```ruby
FactoryBot.define do
  factory :story do
    sequence(:hn_id) { |n| 44_000_000 + n }
    title { "Example story" }
    url { "https://example.com/article" }
    by { "alice" }
    score { 10 }
    descendants { 2 }
    story_type { "story" }
    hn_created_at { 1.hour.ago }
    first_seen_at { 1.hour.ago }
    last_polled_at { Time.current }
    tracking_status { "active" }
  end
end
```

- [ ] **Step 3: Run — expect FAIL**

Run: `bin/rspec spec/models/story_spec.rb`
Expected: FAIL — Story undefined.

- [ ] **Step 4: Migration**

```bash
bin/rails generate migration CreateStories
```

Edit the migration:
```ruby
class CreateStories < ActiveRecord::Migration[8.0]
  def change
    create_table :stories do |t|
      t.bigint :hn_id, null: false
      t.string :title
      t.string :url
      t.string :by
      t.integer :score, null: false, default: 0
      t.integer :descendants, null: false, default: 0
      t.string :story_type
      t.text :text
      t.datetime :hn_created_at
      t.datetime :first_seen_at
      t.datetime :last_polled_at
      t.string :tracking_status, null: false, default: "active"
      t.datetime :archived_at
      t.timestamps
    end
    add_index :stories, :hn_id, unique: true
    add_index :stories, :last_polled_at
    add_index :stories, :tracking_status, where: "tracking_status = 'active'",
              name: "index_stories_on_active"
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 5: Model**

Create `app/models/story.rb`:
```ruby
class Story < ApplicationRecord
  TRACKING_STATUSES = %w[active archived].freeze

  has_many :story_snapshots, dependent: :destroy
  has_many :matches, dependent: :destroy

  validates :hn_id, presence: true, uniqueness: true
  validates :tracking_status, inclusion: { in: TRACKING_STATUSES }

  scope :active, -> { where(tracking_status: "active") }
  scope :archived, -> { where(tracking_status: "archived") }

  def age_hours
    return nil unless hn_created_at
    (Time.current - hn_created_at) / 1.hour
  end

  def active?
    tracking_status == "active"
  end

  def archived?
    tracking_status == "archived"
  end

  def archive!
    update!(tracking_status: "archived", archived_at: Time.current)
  end
end
```

- [ ] **Step 6: Run — expect PASS**

Run: `bin/rspec spec/models/story_spec.rb`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Story model with tracking status"
```

---

## Task 3: StorySnapshot model + migration

**Files:**
- Create: `db/migrate/*_create_story_snapshots.rb`
- Create: `app/models/story_snapshot.rb`
- Create: `spec/factories/story_snapshots.rb`
- Create: `spec/models/story_snapshot_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/models/story_snapshot_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe StorySnapshot, type: :model do
  it "belongs to a story" do
    story = create(:story)
    snap = build(:story_snapshot, story: story)
    expect(snap).to be_valid
  end

  it "requires captured_at" do
    expect(build(:story_snapshot, captured_at: nil)).not_to be_valid
  end

  it "requires score" do
    expect(build(:story_snapshot, score: nil)).not_to be_valid
  end
end
```

- [ ] **Step 2: Factory**

Create `spec/factories/story_snapshots.rb`:
```ruby
FactoryBot.define do
  factory :story_snapshot do
    story
    score { 10 }
    descendants { 2 }
    captured_at { Time.current }
  end
end
```

- [ ] **Step 3: Run — expect FAIL**

Run: `bin/rspec spec/models/story_snapshot_spec.rb`

- [ ] **Step 4: Migration**

```bash
bin/rails generate migration CreateStorySnapshots story:references score:integer descendants:integer captured_at:datetime
```

Edit to add defaults + nulls:
```ruby
class CreateStorySnapshots < ActiveRecord::Migration[8.0]
  def change
    create_table :story_snapshots do |t|
      t.references :story, null: false, foreign_key: true
      t.integer :score, null: false
      t.integer :descendants, null: false, default: 0
      t.datetime :captured_at, null: false
      t.timestamps
    end
    add_index :story_snapshots, [:story_id, :captured_at]
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 5: Model**

Create `app/models/story_snapshot.rb`:
```ruby
class StorySnapshot < ApplicationRecord
  belongs_to :story

  validates :score, :captured_at, presence: true
end
```

- [ ] **Step 6: Run — expect PASS**

Run: `bin/rspec spec/models/story_snapshot_spec.rb`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add StorySnapshot model"
```

---

## Task 4: Match + Notification models + migrations

**Files:**
- Create: `db/migrate/*_create_matches.rb`
- Create: `db/migrate/*_create_notifications.rb`
- Create: `app/models/match.rb`
- Create: `app/models/notification.rb`
- Create: `spec/factories/matches.rb`
- Create: `spec/factories/notifications.rb`
- Create: `spec/models/match_spec.rb`

- [ ] **Step 1: Match spec**

Create `spec/models/match_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Match, type: :model do
  it "belongs to story and topic" do
    match = build(:match)
    expect(match).to be_valid
  end

  it "enforces uniqueness on (story, topic)" do
    m = create(:match)
    dup = build(:match, story: m.story, topic: m.topic)
    expect(dup).not_to be_valid
  end

  it "is visible when not dismissed and not posted and above threshold" do
    m = create(:match)
    expect(Match.visible).to include(m)
  end

  it "is hidden when dismissed" do
    m = create(:match, dismissed_at: Time.current)
    expect(Match.visible).not_to include(m)
  end

  it "is hidden when posted" do
    m = create(:match, posted_at: Time.current)
    expect(Match.visible).not_to include(m)
  end

  it "is hidden when relevance_score is below threshold (rejected classification)" do
    m = create(:match, relevance_score: 0.4)
    expect(Match.visible).not_to include(m)
  end
end
```

- [ ] **Step 2: Factories**

Create `spec/factories/matches.rb`:
```ruby
FactoryBot.define do
  factory :match do
    story
    topic
    relevance_score { 0.8 }
    reason { "Directly discusses AI agents." }
    velocity_score { 20.0 }
    matched_at { Time.current }
  end
end
```

Create `spec/factories/notifications.rb`:
```ruby
FactoryBot.define do
  factory :notification do
    match
    channel { "web_push" }
    status { "pending" }
    association :target, factory: :push_subscription
  end
end
```

- [ ] **Step 3: Run — expect FAIL**

Run: `bin/rspec spec/models/match_spec.rb`

- [ ] **Step 4: Migrations**

```bash
bin/rails generate migration CreateMatches
bin/rails generate migration CreateNotifications
```

Edit matches migration:
```ruby
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
    add_index :matches, [:story_id, :topic_id], unique: true
    add_index :matches, [:topic_id, :matched_at]
  end
end
```

Edit notifications migration (with fan-out target columns — see 2026-04-20 amendment):
```ruby
class CreateNotifications < ActiveRecord::Migration[8.0]
  def change
    create_table :notifications do |t|
      t.references :match, null: false, foreign_key: true
      t.string :channel, null: false
      t.string :target_type, null: false  # "PushSubscription" or "TopicSubscription"
      t.bigint :target_id, null: false
      t.string :status, null: false, default: "pending"
      t.datetime :sent_at
      t.text :error
      t.timestamps
    end
    add_index :notifications,
              [:match_id, :channel, :target_type, :target_id],
              unique: true,
              name: "index_notifications_on_match_channel_target"
  end
end
```

Run: `bin/rails db:migrate`

- [ ] **Step 5: Models**

Create `app/models/match.rb`:
```ruby
class Match < ApplicationRecord
  CHANNELS = %w[web_push discord].freeze

  belongs_to :story
  belongs_to :topic
  has_many :notifications, dependent: :destroy

  validates :matched_at, presence: true
  validates :story_id, uniqueness: { scope: :topic_id }

  scope :visible, lambda {
    threshold = TrackingConfig.match[:min_relevance_score]
    where(dismissed_at: nil, posted_at: nil)
      .where("relevance_score >= ?", threshold)
  }
  scope :recent, -> { order(matched_at: :desc) }
end
```

Create `app/models/notification.rb`:
```ruby
class Notification < ApplicationRecord
  CHANNELS = %w[web_push discord].freeze
  STATUSES = %w[pending sent failed].freeze
  TARGET_TYPES = %w[PushSubscription TopicSubscription].freeze

  belongs_to :match
  belongs_to :target, polymorphic: true

  validates :channel, inclusion: { in: CHANNELS }
  validates :status, inclusion: { in: STATUSES }
  validates :target_type, inclusion: { in: TARGET_TYPES }
  validates :target_id, uniqueness: { scope: [:match_id, :channel, :target_type] }
end
```

- [ ] **Step 6: Run — expect PASS**

Run: `bin/rspec spec/models/match_spec.rb`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add Match and Notification models"
```

---

## Task 5: VelocityCalculator service (pure function)

**Files:**
- Create: `app/services/velocity_calculator.rb`
- Create: `spec/services/velocity_calculator_spec.rb`

- [ ] **Step 1: Spec first**

Create `spec/services/velocity_calculator_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe VelocityCalculator do
  describe ".rolling_points_per_hour" do
    it "returns [] when fewer than 2 snapshots" do
      snap = build_snaps([[Time.current, 10]])
      expect(VelocityCalculator.rolling_points_per_hour(snap)).to eq([])
    end

    it "computes points/hour between consecutive snapshots" do
      t0 = Time.current - 3.hours
      snaps = build_snaps([[t0, 0], [t0 + 1.hour, 10], [t0 + 2.hours, 25]])
      result = VelocityCalculator.rolling_points_per_hour(snaps)
      expect(result).to eq([10.0, 15.0])
    end

    it "handles fractional hours" do
      t0 = Time.current - 2.hours
      snaps = build_snaps([[t0, 0], [t0 + 30.minutes, 20]])
      expect(VelocityCalculator.rolling_points_per_hour(snaps)).to eq([40.0])
    end

    it "returns 0 for zero-duration gaps (dedup safety)" do
      t = Time.current
      snaps = build_snaps([[t, 10], [t, 20]])
      expect(VelocityCalculator.rolling_points_per_hour(snaps)).to eq([0.0])
    end
  end

  describe ".current_velocity" do
    it "returns the most recent rolling velocity" do
      t0 = Time.current - 3.hours
      snaps = build_snaps([[t0, 0], [t0 + 1.hour, 10], [t0 + 2.hours, 25]])
      expect(VelocityCalculator.current_velocity(snaps)).to eq(15.0)
    end

    it "returns nil when insufficient data" do
      expect(VelocityCalculator.current_velocity([])).to be_nil
    end
  end

  def build_snaps(pairs)
    pairs.map do |captured_at, score|
      OpenStruct.new(captured_at: captured_at, score: score)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/services/velocity_calculator_spec.rb`

- [ ] **Step 3: Implement**

Create `app/services/velocity_calculator.rb`:
```ruby
class VelocityCalculator
  class << self
    # snapshots: Array of objects with `captured_at` and `score`, chronological asc.
    # Returns Array<Float> of points/hour for each consecutive pair.
    def rolling_points_per_hour(snapshots)
      return [] if snapshots.size < 2

      snapshots.each_cons(2).map do |prev, current|
        elapsed_seconds = current.captured_at - prev.captured_at
        next 0.0 if elapsed_seconds <= 0

        elapsed_hours = elapsed_seconds / 3600.0
        (current.score - prev.score) / elapsed_hours
      end
    end

    def current_velocity(snapshots)
      rolling_points_per_hour(snapshots).last
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/services/velocity_calculator_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add VelocityCalculator service"
```

---

## Task 6: KeywordMatcher service

**Files:**
- Create: `app/services/keyword_matcher.rb`
- Create: `spec/services/keyword_matcher_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/services/keyword_matcher_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe KeywordMatcher do
  describe ".matches?" do
    let(:story) do
      build(:story,
            title: "OpenAI releases GPT-4o agent framework",
            url: "https://openai.com/blog/agents",
            text: nil)
    end

    it "matches when keyword appears in title (case-insensitive)" do
      expect(KeywordMatcher.matches?(story, ["agent"])).to be true
      expect(KeywordMatcher.matches?(story, ["AGENT"])).to be true
    end

    it "matches against URL host and path" do
      expect(KeywordMatcher.matches?(story, ["openai"])).to be true
    end

    it "matches against Ask HN text body" do
      ask = build(:story, title: "Ask HN", url: nil, text: "Using Rust for embedded systems")
      expect(KeywordMatcher.matches?(ask, ["rust"])).to be true
    end

    it "returns false when no keyword matches" do
      expect(KeywordMatcher.matches?(story, ["kubernetes"])).to be false
    end

    it "is safe against SQL-like special chars" do
      s = build(:story, title: "Story with 100% improvement")
      expect(KeywordMatcher.matches?(s, ["100%"])).to be true
    end

    it "treats whole-keyword-substring (no word boundary)" do
      s = build(:story, title: "Rustacean unite!")
      expect(KeywordMatcher.matches?(s, ["rust"])).to be true
    end

    it "ignores blank keywords" do
      expect(KeywordMatcher.matches?(story, ["", " "])).to be false
    end
  end

  describe ".matching_topics" do
    let(:story) { create(:story, title: "Rust 2024 roadmap") }

    it "returns active topics whose keywords match (no user scoping)" do
      rust = create(:topic, name: "Rust", keywords: ["rust"], active: true)
      ai   = create(:topic, name: "AI", keywords: ["gpt", "llm"], active: true)
      paused = create(:topic, name: "Rust paused", keywords: ["rust"], active: false)

      result = KeywordMatcher.matching_topics(story, Topic.all)
      expect(result).to contain_exactly(rust)
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/services/keyword_matcher_spec.rb`

- [ ] **Step 3: Implement**

Create `app/services/keyword_matcher.rb`:
```ruby
class KeywordMatcher
  class << self
    def matches?(story, keywords)
      text = searchable_text(story)
      return false if text.blank?

      keywords.any? do |kw|
        next false if kw.to_s.strip.empty?
        text.include?(kw.downcase.strip)
      end
    end

    def matching_topics(story, topics_scope)
      topics_scope.where(active: true).select { |topic| matches?(story, topic.keywords) }
    end

    private

    def searchable_text(story)
      [story.title, story.url, story.text].compact.join(" ").downcase
    end
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/services/keyword_matcher_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add KeywordMatcher service"
```

---

## Task 7: HN API client service

**Files:**
- Modify: `Gemfile` (add faraday)
- Create: `app/services/hn/client.rb`
- Create: `spec/services/hn/client_spec.rb`

- [ ] **Step 1: Add faraday**

Append to `Gemfile`:
```ruby
gem "faraday"
gem "faraday-retry"
```

Run: `bundle install`. Commit:
```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add faraday"
```

- [ ] **Step 2: Spec first**

Create `spec/services/hn/client_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Hn::Client do
  let(:client) { described_class.new }

  describe "#top_story_ids" do
    it "returns array of IDs from /topstories.json" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json")
        .to_return(status: 200, body: "[1, 2, 3]", headers: { "Content-Type" => "application/json" })

      expect(client.top_story_ids).to eq([1, 2, 3])
    end
  end

  describe "#new_story_ids" do
    it "returns array of IDs from /newstories.json" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/newstories.json")
        .to_return(status: 200, body: "[10, 11]", headers: { "Content-Type" => "application/json" })

      expect(client.new_story_ids).to eq([10, 11])
    end
  end

  describe "#item" do
    it "returns a parsed hash for a live story" do
      body = {
        id: 44_000_001, type: "story", by: "alice", title: "Hello",
        url: "https://example.com", score: 42, descendants: 7, time: 1_700_000_000,
      }.to_json
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/44000001.json")
        .to_return(status: 200, body: body, headers: { "Content-Type" => "application/json" })

      expect(client.item(44_000_001)).to include(id: 44_000_001, title: "Hello", score: 42)
    end

    it "returns nil for deleted stories" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/999.json")
        .to_return(status: 200, body: '{"id":999,"deleted":true}', headers: { "Content-Type" => "application/json" })

      expect(client.item(999)).to be_nil
    end

    it "returns nil for null response (unknown id)" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/0.json")
        .to_return(status: 200, body: "null", headers: { "Content-Type" => "application/json" })

      expect(client.item(0)).to be_nil
    end

    it "raises on 5xx after retries" do
      stub_request(:get, "https://hacker-news.firebaseio.com/v0/item/1.json")
        .to_return(status: 503)

      expect { client.item(1) }.to raise_error(Hn::Client::RequestError)
    end
  end
end
```

- [ ] **Step 3: Run — expect FAIL**

Run: `bin/rspec spec/services/hn/client_spec.rb`

- [ ] **Step 4: Implement**

Create `app/services/hn/client.rb`:
```ruby
module Hn
  class Client
    BASE_URL = "https://hacker-news.firebaseio.com/v0"

    class RequestError < StandardError; end

    def initialize(connection: default_connection)
      @connection = connection
    end

    def top_story_ids
      parse(get("topstories.json"))
    end

    def new_story_ids
      parse(get("newstories.json"))
    end

    def best_story_ids
      parse(get("beststories.json"))
    end

    def item(hn_id)
      data = parse(get("item/#{hn_id}.json"))
      return nil if data.nil? || data[:deleted] || data[:dead]
      data
    end

    private

    attr_reader :connection

    def get(path)
      response = connection.get(path)
      raise RequestError, "HN #{path}: #{response.status}" unless response.success?
      response.body
    end

    def parse(body)
      return nil if body.nil? || body == "null"
      JSON.parse(body, symbolize_names: true)
    rescue JSON::ParserError => e
      raise RequestError, "Invalid JSON from HN: #{e.message}"
    end

    def default_connection
      Faraday.new(url: BASE_URL) do |f|
        f.request :retry, max: 3, interval: 0.5,
                  exceptions: [Faraday::ConnectionFailed, Faraday::TimeoutError]
        f.response :raise_error
        f.options.timeout = 10
        f.options.open_timeout = 5
      end
    end
  end
end
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rspec spec/services/hn/client_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add HN API client with retry and error handling"
```

---

## Task 8: FetchStoryJob — upsert + snapshot + archive + candidate

**Files:**
- Create: `app/jobs/fetch_story_job.rb`
- Create: `spec/jobs/fetch_story_job_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/jobs/fetch_story_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe FetchStoryJob, type: :job do
  let(:hn_id) { 44_000_123 }
  let(:item_url) { "https://hacker-news.firebaseio.com/v0/item/#{hn_id}.json" }

  def stub_item(attrs = {})
    defaults = {
      id: hn_id, type: "story", by: "alice", title: "Hello",
      url: "https://example.com", score: 42, descendants: 7,
      time: 30.minutes.ago.to_i,
    }
    stub_request(:get, item_url).to_return(
      status: 200,
      body: defaults.merge(attrs).to_json,
      headers: { "Content-Type" => "application/json" }
    )
  end

  describe "on first fetch of a new story" do
    before { stub_item }

    it "creates story + snapshot and enqueues MatchJob (new story is always candidate)" do
      expect {
        FetchStoryJob.new.perform(hn_id)
      }.to change(Story, :count).by(1)
       .and change(StorySnapshot, :count).by(1)

      expect(MatchJob).to have_been_enqueued.with(Story.last.id)
    end
  end

  describe "on subsequent fetch of an existing story" do
    let!(:story) do
      create(:story, hn_id: hn_id, score: 20, descendants: 3,
                     hn_created_at: 2.hours.ago, first_seen_at: 2.hours.ago,
                     last_polled_at: 1.hour.ago)
    end

    before do
      create(:story_snapshot, story: story, score: 20, descendants: 3, captured_at: 1.hour.ago)
    end

    it "updates score + inserts snapshot + does not enqueue when velocity below threshold" do
      stub_item(score: 22, descendants: 4)

      expect { FetchStoryJob.new.perform(hn_id) }.not_to have_enqueued_job(MatchJob)
      expect(story.reload.score).to eq(22)
      expect(story.story_snapshots.count).to eq(2)
    end

    it "enqueues MatchJob when velocity crosses threshold" do
      # From score 20 → 60 in 1 hour = 40 pts/hr, above threshold (15), and total ≥ 30
      stub_item(score: 60, descendants: 10)
      expect { FetchStoryJob.new.perform(hn_id) }.to have_enqueued_job(MatchJob).with(story.id)
    end
  end

  describe "archival decisions" do
    let!(:story) do
      create(:story, hn_id: hn_id,
                     hn_created_at: 80.hours.ago,
                     first_seen_at: 80.hours.ago,
                     last_polled_at: 30.minutes.ago,
                     score: 100)
    end

    before { stub_item(score: 100, time: 80.hours.ago.to_i) }

    it "archives stories older than hard cutoff" do
      FetchStoryJob.new.perform(hn_id)
      expect(story.reload).to be_archived
    end
  end

  describe "deleted stories" do
    it "archives if already tracked, otherwise no-op" do
      create(:story, hn_id: hn_id)
      stub_request(:get, item_url).to_return(
        status: 200, body: '{"id":44000123,"deleted":true}',
        headers: { "Content-Type" => "application/json" }
      )
      FetchStoryJob.new.perform(hn_id)
      expect(Story.find_by(hn_id: hn_id)).to be_archived
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/jobs/fetch_story_job_spec.rb`

- [ ] **Step 3: Implement**

Create `app/jobs/fetch_story_job.rb`:
```ruby
class FetchStoryJob < ApplicationJob
  queue_as :default

  def perform(hn_id)
    data = Hn::Client.new.item(hn_id)

    if data.nil?
      if (existing = Story.find_by(hn_id: hn_id)) && existing.active?
        existing.archive!
      end
      return
    end

    story = Story.find_or_initialize_by(hn_id: hn_id)
    is_new = story.new_record?
    apply_item_attributes(story, data)
    story.save!

    snapshot = story.story_snapshots.create!(
      score: story.score,
      descendants: story.descendants,
      captured_at: Time.current
    )

    return unless story.active?

    apply_archival_rules!(story)
    return unless story.active?

    enqueue_match = is_new || velocity_candidate?(story)
    MatchJob.perform_later(story.id) if enqueue_match
  end

  private

  def apply_item_attributes(story, data)
    story.title        = data[:title]
    story.url          = data[:url]
    story.by           = data[:by]
    story.score        = data[:score] || 0
    story.descendants  = data[:descendants] || 0
    story.story_type   = data[:type]
    story.text         = data[:text]
    story.hn_created_at ||= Time.at(data[:time]) if data[:time]
    story.first_seen_at ||= Time.current
    story.last_polled_at = Time.current
  end

  def apply_archival_rules!(story)
    cfg = TrackingConfig.archive
    age_hours = story.age_hours

    if age_hours && age_hours > cfg[:hard_cutoff_hours]
      story.archive!
      return
    end

    snapshots = story.story_snapshots.order(:captured_at).last(cfg[:flat_snapshots_required] + 1)

    if age_hours && age_hours > cfg[:cooling_age_hours]
      velocities = VelocityCalculator.rolling_points_per_hour(snapshots)
      if velocities.size >= cfg[:flat_snapshots_required] &&
         velocities.last(cfg[:flat_snapshots_required]).all? { |v| v < cfg[:cooling_points_per_hour] }
        story.archive!
        return
      end
    end

    if snapshots.size >= cfg[:flat_snapshots_required] + 1
      recent = snapshots.last(cfg[:flat_snapshots_required] + 1)
      if recent.each_cons(2).all? { |a, b| a.score == b.score && a.descendants == b.descendants }
        story.archive!
      end
    end
  end

  def velocity_candidate?(story)
    cfg = TrackingConfig.velocity_candidate_threshold
    snapshots = story.story_snapshots.order(:captured_at).last(2)
    velocity = VelocityCalculator.current_velocity(snapshots)
    return false if velocity.nil?

    velocity >= cfg[:points_per_hour] && story.score >= cfg[:minimum_score]
  end
end
```

Create a stub `MatchJob` so references resolve:
Create `app/jobs/match_job.rb`:
```ruby
class MatchJob < ApplicationJob
  queue_as :default

  def perform(story_id)
    # Implementation added in Task 11
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/jobs/fetch_story_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add FetchStoryJob with snapshot, archival, and candidate detection"
```

---

## Task 9: FetchFeedsJob — poller entry point

**Files:**
- Create: `app/jobs/fetch_feeds_job.rb`
- Create: `spec/jobs/fetch_feeds_job_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/jobs/fetch_feeds_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe FetchFeedsJob, type: :job do
  before do
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/topstories.json")
      .to_return(status: 200, body: "[100, 101, 102]",
                 headers: { "Content-Type" => "application/json" })
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/newstories.json")
      .to_return(status: 200, body: "[102, 103]",
                 headers: { "Content-Type" => "application/json" })
  end

  it "enqueues FetchStoryJob for each unique id in top+new (frequent mode)" do
    expect {
      FetchFeedsJob.new.perform("frequent")
    }.to have_enqueued_job(FetchStoryJob).exactly(4).times
  end

  it "refreshes young active stories that haven't been polled recently" do
    young = create(:story, hn_id: 200, hn_created_at: 1.hour.ago,
                   last_polled_at: 20.minutes.ago, tracking_status: "active")
    stale = create(:story, hn_id: 201, hn_created_at: 10.hours.ago,
                   last_polled_at: 1.hour.ago, tracking_status: "active")

    FetchFeedsJob.new.perform("frequent")

    expect(FetchStoryJob).to have_been_enqueued.with(200)
    expect(FetchStoryJob).not_to have_been_enqueued.with(201)
  end

  it "skips archived stories" do
    create(:story, hn_id: 300, tracking_status: "archived")
    # ensure 300 isn't in feeds (it isn't per stubs)
    FetchFeedsJob.new.perform("frequent")
    expect(FetchStoryJob).not_to have_been_enqueued.with(300)
  end

  it "hits beststories.json on full mode" do
    stub_request(:get, "https://hacker-news.firebaseio.com/v0/beststories.json")
      .to_return(status: 200, body: "[400]",
                 headers: { "Content-Type" => "application/json" })

    FetchFeedsJob.new.perform("full")

    expect(FetchStoryJob).to have_been_enqueued.with(400)
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/jobs/fetch_feeds_job_spec.rb`

- [ ] **Step 3: Implement**

Create `app/jobs/fetch_feeds_job.rb`:
```ruby
class FetchFeedsJob < ApplicationJob
  queue_as :default

  YOUNG_AGE_HOURS = 6
  YOUNG_REPOLL_MINUTES = 5
  DEFAULT_REPOLL_MINUTES = 30

  def perform(mode = "frequent")
    client = Hn::Client.new
    ids = Set.new

    ids.merge(client.top_story_ids)
    ids.merge(client.new_story_ids)
    ids.merge(client.best_story_ids) if mode == "full"

    ids.each { |id| FetchStoryJob.perform_later(id) }

    Story.active.where("hn_created_at > ?", YOUNG_AGE_HOURS.hours.ago)
         .where("last_polled_at < ?", YOUNG_REPOLL_MINUTES.minutes.ago)
         .find_each { |s| FetchStoryJob.perform_later(s.hn_id) }

    Story.active.where("hn_created_at <= ?", YOUNG_AGE_HOURS.hours.ago)
         .where("last_polled_at < ?", DEFAULT_REPOLL_MINUTES.minutes.ago)
         .find_each { |s| FetchStoryJob.perform_later(s.hn_id) }
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/jobs/fetch_feeds_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add FetchFeedsJob with young-story and default re-poll logic"
```

---

## Task 10: OpenAI Matcher service (with JSON retry)

**Files:**
- Modify: `Gemfile`
- Create: `app/services/openai/matcher.rb`
- Create: `spec/services/openai/matcher_spec.rb`
- Create: `spec/fixtures/vcr_cassettes/openai/matcher_*.yml` (recorded)

- [ ] **Step 1: Add ruby-openai gem**

Append to `Gemfile`:
```ruby
gem "ruby-openai"
```

Run: `bundle install`. Commit:
```bash
git add Gemfile Gemfile.lock
git commit -m "chore: add ruby-openai gem"
```

- [ ] **Step 2: Configure OpenAI client**

Create `config/initializers/openai.rb`:
```ruby
OpenAI.configure do |c|
  c.access_token = ENV.fetch("OPENAI_API_KEY") { Rails.application.credentials.dig(:openai, :api_key) }
  c.request_timeout = 30
end
```

- [ ] **Step 3: Spec first (uses stubs, not VCR, for deterministic retry tests)**

Create `spec/services/openai/matcher_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe Openai::Matcher do
  let(:story) { build(:story, title: "OpenAI releases agent framework", url: "https://openai.com/x") }
  let(:topic) { build(:topic, name: "AI agents", keywords: ["agent", "LLM"]) }

  def stub_openai(responses)
    client = instance_double(OpenAI::Client)
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(*responses)
    client
  end

  def valid_response(score:, reason:)
    {
      "choices" => [
        { "message" => { "content" => { score: score, reason: reason }.to_json } }
      ]
    }
  end

  it "returns the parsed result on first success" do
    stub_openai([valid_response(score: 0.8, reason: "Directly about agents")])

    result = Openai::Matcher.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.8)
    expect(result[:reason]).to eq("Directly about agents")
  end

  it "retries up to 3 times when response is not valid JSON" do
    bad = { "choices" => [{ "message" => { "content" => "Sure, here's..." } }] }
    stub_openai([bad, bad, valid_response(score: 0.7, reason: "ok")])

    result = Openai::Matcher.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.7)
  end

  it "returns score 0 after 3 failed JSON retries" do
    bad = { "choices" => [{ "message" => { "content" => "not json" } }] }
    stub_openai([bad, bad, bad, bad])

    result = Openai::Matcher.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.0)
    expect(result[:reason]).to include("invalid")
  end

  it "returns score 0 when JSON is parseable but missing keys" do
    wrong_shape = { "choices" => [{ "message" => { "content" => '{"foo":1}' } }] }
    stub_openai([wrong_shape] * 4)

    result = Openai::Matcher.new.call(story: story, topic: topic)

    expect(result[:score]).to eq(0.0)
  end
end
```

- [ ] **Step 4: Run — expect FAIL**

Run: `bin/rspec spec/services/openai/matcher_spec.rb`

- [ ] **Step 5: Implement**

Create `app/services/openai/matcher.rb`:
```ruby
module Openai
  class Matcher
    MODEL = "gpt-4o-mini"
    MAX_JSON_RETRIES = 3

    def initialize(client: OpenAI::Client.new)
      @client = client
    end

    def call(story:, topic:)
      messages = [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(story: story, topic: topic) },
      ]

      MAX_JSON_RETRIES.times do |attempt|
        response = chat(messages)
        content = response.dig("choices", 0, "message", "content").to_s

        parsed = parse(content)
        return parsed if parsed

        messages << { role: "assistant", content: content }
        messages << {
          role: "system",
          content: "Your previous response was not valid JSON. Respond with ONLY a JSON object " \
                   "with keys 'score' (float 0-1) and 'reason' (string). No prose, no markdown fences.",
        }
      end

      Rails.logger.warn("[Openai::Matcher] exhausted retries for story=#{story.id} topic=#{topic.id}")
      { score: 0.0, reason: "invalid response from classifier" }
    end

    private

    attr_reader :client

    def chat(messages)
      client.chat(parameters: {
        model: MODEL,
        messages: messages,
        response_format: { type: "json_object" },
        temperature: 0.2,
      })
    end

    def parse(content)
      data = JSON.parse(content)
      return nil unless data.is_a?(Hash) && data.key?("score") && data.key?("reason")

      score = data["score"].to_f
      return nil unless score.between?(0.0, 1.0)

      { score: score, reason: data["reason"].to_s }
    rescue JSON::ParserError
      nil
    end

    def system_prompt
      <<~PROMPT
        You are a strict classifier that decides if a Hacker News story is relevant to a given
        editorial topic. Respond with ONLY a JSON object: {"score": float 0-1, "reason": string}.
        A score of 1.0 means the story is clearly and primarily about the topic. 0.0 means not
        relevant at all. 0.6+ is the threshold for "worth notifying an editor".
        The reason should be one sentence suitable as a social-media post opener.
      PROMPT
    end

    def user_prompt(story:, topic:)
      <<~PROMPT
        Topic: #{topic.name}
        Topic keywords (may be narrower than the name): #{topic.keywords.join(", ")}

        Story:
          Title: #{story.title}
          URL: #{story.url || '(none)'}
          Text: #{(story.text || '').truncate(500)}

        Classify: is this story relevant to the topic?
      PROMPT
    end
  end
end
```

- [ ] **Step 6: Run — expect PASS**

Run: `bin/rspec spec/services/openai/matcher_spec.rb`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add OpenAI Matcher service with JSON retry loop"
```

---

## Task 11: MatchJob — prefilter + LLM + match creation

**Files:**
- Modify: `app/jobs/match_job.rb`
- Create: `spec/jobs/match_job_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/jobs/match_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe MatchJob, type: :job do
  let(:story) { create(:story, title: "OpenAI ships new agent SDK") }

  def stub_matcher(score:, reason: "ok")
    matcher = instance_double(Openai::Matcher)
    allow(Openai::Matcher).to receive(:new).and_return(matcher)
    allow(matcher).to receive(:call).and_return({ score: score, reason: reason })
    matcher
  end

  context "with matching topic" do
    let!(:topic) { create(:topic, keywords: ["agent", "llm"]) }
    before { create(:story_snapshot, story: story, score: 60, captured_at: 30.minutes.ago) }
    before { create(:story_snapshot, story: story, score: 90, captured_at: Time.current) }

    it "creates a Match (per story, topic) when score >= threshold" do
      stub_matcher(score: 0.8, reason: "Directly about agents")

      expect { MatchJob.new.perform(story.id) }.to change(Match, :count).by(1)

      match = Match.last
      expect(match.topic).to eq(topic)
      expect(match.relevance_score).to eq(0.8)
      expect(match.reason).to eq("Directly about agents")
      expect(match.velocity_score).to be > 0
    end

    it "still creates a Match when score below threshold (so we don't reclassify) but does NOT enqueue NotifyJob" do
      stub_matcher(score: 0.4, reason: "Tangentially related")

      expect { MatchJob.new.perform(story.id) }.to change(Match, :count).by(1)
      expect(NotifyJob).not_to have_been_enqueued

      match = Match.last
      expect(match.relevance_score).to eq(0.4)
    end

    it "is idempotent — does not duplicate a match (or re-classify) on re-run, regardless of score" do
      matcher = stub_matcher(score: 0.8)
      MatchJob.new.perform(story.id)

      expect { MatchJob.new.perform(story.id) }.not_to change(Match, :count)
      expect(matcher).to have_received(:call).once
    end

    it "does not re-classify a (story, topic) that was previously rejected" do
      matcher = stub_matcher(score: 0.4)
      MatchJob.new.perform(story.id)

      expect { MatchJob.new.perform(story.id) }.not_to change(Match, :count)
      expect(matcher).to have_received(:call).once
    end

    it "classifies once per topic regardless of subscriber count" do
      create_list(:topic_subscription, 3, topic: topic)
      matcher = stub_matcher(score: 0.8)

      MatchJob.new.perform(story.id)

      expect(matcher).to have_received(:call).once
      expect(Match.where(story: story, topic: topic).count).to eq(1)
    end

    it "enqueues NotifyJob for new matches" do
      stub_matcher(score: 0.8)
      expect { MatchJob.new.perform(story.id) }.to have_enqueued_job(NotifyJob)
    end
  end

  context "with no matching topic" do
    let!(:topic) { create(:topic, keywords: ["kubernetes"]) }

    it "does not call OpenAI" do
      expect(Openai::Matcher).not_to receive(:new)
      MatchJob.new.perform(story.id)
    end
  end

  context "inactive topics" do
    let!(:_inactive) { create(:topic, keywords: ["agent"], active: false) }

    it "is skipped by the prefilter" do
      expect(Openai::Matcher).not_to receive(:new)
      MatchJob.new.perform(story.id)
    end
  end

  context "daily budget exceeded" do
    let!(:topic) { create(:topic, keywords: ["agent"]) }

    it "skips classification when today's classification count exceeds budget" do
      allow(TrackingConfig).to receive(:match).and_return(
        min_relevance_score: 0.6, daily_classification_budget: 0
      )
      stub_matcher(score: 0.8)
      expect { MatchJob.new.perform(story.id) }.not_to change(Match, :count)
    end
  end
end
```

- [ ] **Step 2: Stub NotifyJob so specs can reference it**

Create `app/jobs/notify_job.rb`:
```ruby
class NotifyJob < ApplicationJob
  queue_as :default

  def perform(match_id)
    # Implementation in Plan 3
  end
end
```

- [ ] **Step 3: Run — expect FAIL**

Run: `bin/rspec spec/jobs/match_job_spec.rb`

- [ ] **Step 4: Implement**

Replace `app/jobs/match_job.rb`:
```ruby
class MatchJob < ApplicationJob
  queue_as :default

  def perform(story_id)
    story = Story.find(story_id)
    return if story.archived?

    return unless within_daily_budget?

    candidate_topics = KeywordMatcher.matching_topics(story, Topic.where(active: true))
    return if candidate_topics.empty?

    matcher = Openai::Matcher.new
    threshold = TrackingConfig.match[:min_relevance_score]

    candidate_topics.each do |topic|
      next if Match.exists?(story_id: story.id, topic_id: topic.id)

      result = matcher.call(story: story, topic: topic)
      record_classification

      match = Match.create!(
        story: story,
        topic: topic,
        relevance_score: result[:score],
        reason: result[:reason],
        velocity_score: current_velocity(story),
        matched_at: Time.current,
      )
      NotifyJob.perform_later(match.id) if result[:score] >= threshold
    rescue ActiveRecord::RecordNotUnique
      next
    end
  end

  private

  def current_velocity(story)
    snapshots = story.story_snapshots.order(:captured_at).last(2)
    VelocityCalculator.current_velocity(snapshots) || 0.0
  end

  def within_daily_budget?
    budget = TrackingConfig.match[:daily_classification_budget]
    today_count < budget
  end

  def record_classification
    Rails.cache.increment(classification_cache_key, 1, expires_in: 36.hours)
  end

  def today_count
    (Rails.cache.read(classification_cache_key) || 0).to_i
  end

  def classification_cache_key
    "openai:classifications:#{Date.current}"
  end
end
```

- [ ] **Step 5: Configure cache for test env to use memory**

Ensure `config/environments/test.rb` has:
```ruby
  config.cache_store = :memory_store
```
(Rails default is usually null_store in test; we need increments to work.)

- [ ] **Step 6: Run — expect PASS**

Run: `bin/rspec spec/jobs/match_job_spec.rb`

- [ ] **Step 7: Commit**

```bash
git add -A
git commit -m "feat: add MatchJob with prefilter, OpenAI call, budget guard"
```

---

## Task 12: BackfillSubscriptionJob

**Files:**
- Create: `app/jobs/backfill_subscription_job.rb`
- Create: `spec/jobs/backfill_subscription_job_spec.rb`

> **2026-04-20 amendment:** renamed from `BackfillTopicJob`. In the shared-catalog model a brand-new topic has zero subscribers (no notifications to send), so the backfill trigger moves from `Topic#create` to `TopicSubscription#create`. The job takes a `topic_subscription_id` argument so we can resolve the subscriber's user if we later need to scope the work.

- [ ] **Step 1: Spec**

Create `spec/jobs/backfill_subscription_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe BackfillSubscriptionJob, type: :job do
  let(:user) { create(:user) }
  let!(:topic) { create(:topic, keywords: ["agent"]) }
  let!(:subscription) { create(:topic_subscription, user: user, topic: topic) }

  it "enqueues MatchJob for each active story from last 24 hours" do
    recent = create_list(:story, 3, hn_created_at: 2.hours.ago)
    _old = create(:story, hn_created_at: 3.days.ago)

    BackfillSubscriptionJob.new.perform(subscription.id)

    recent.each do |s|
      expect(MatchJob).to have_been_enqueued.with(s.id)
    end
  end

  it "does nothing when the topic is inactive" do
    topic.update!(active: false)
    create(:story, hn_created_at: 1.hour.ago)
    BackfillSubscriptionJob.new.perform(subscription.id)
    expect(MatchJob).not_to have_been_enqueued
  end

  it "no-ops when the subscription has been deleted" do
    id = subscription.id
    subscription.destroy
    expect {
      BackfillSubscriptionJob.new.perform(id)
    }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/jobs/backfill_subscription_job_spec.rb`

- [ ] **Step 3: Implement**

Create `app/jobs/backfill_subscription_job.rb`:
```ruby
class BackfillSubscriptionJob < ApplicationJob
  queue_as :default

  BACKFILL_WINDOW = 24.hours

  def perform(topic_subscription_id)
    subscription = TopicSubscription.find_by(id: topic_subscription_id)
    return unless subscription
    return unless subscription.topic.active?

    Story.active.where("hn_created_at > ?", BACKFILL_WINDOW.ago).find_each do |story|
      MatchJob.perform_later(story.id)
    end
  end
end
```

Note: `MatchJob` already skips stories that already have a `Match` for a given topic, so this is safe to run repeatedly (e.g., second subscriber to an already-backfilled topic).

- [ ] **Step 4: Hook into subscription creation**

Edit `app/controllers/topic_subscriptions_controller.rb#create`. After a successful save, enqueue the backfill:
```ruby
if sub.persisted? || sub.save
  BackfillSubscriptionJob.perform_later(sub.id) if sub.previously_new_record?
  redirect_to topics_path, notice: "Subscribed to #{@topic.name}."
else
  # ...
end
```

(Use `previously_new_record?` to avoid re-enqueuing when `find_or_initialize_by` returns an already-persisted record.)

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rspec spec/jobs/backfill_subscription_job_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add BackfillSubscriptionJob triggered on subscription create"
```

---

## Task 13: PruneSnapshotsJob

**Files:**
- Create: `app/jobs/prune_snapshots_job.rb`
- Create: `spec/jobs/prune_snapshots_job_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/jobs/prune_snapshots_job_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe PruneSnapshotsJob, type: :job do
  it "deletes snapshots older than retention window, keeps recent" do
    story = create(:story)
    old = create(:story_snapshot, story: story, captured_at: 10.days.ago)
    fresh = create(:story_snapshot, story: story, captured_at: 1.day.ago)

    PruneSnapshotsJob.new.perform

    expect { old.reload }.to raise_error(ActiveRecord::RecordNotFound)
    expect { fresh.reload }.not_to raise_error
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/jobs/prune_snapshots_job_spec.rb`

- [ ] **Step 3: Implement**

Create `app/jobs/prune_snapshots_job.rb`:
```ruby
class PruneSnapshotsJob < ApplicationJob
  queue_as :low

  def perform
    cutoff = TrackingConfig.snapshot_retention_days.days.ago
    StorySnapshot.where("captured_at < ?", cutoff).delete_all
  end
end
```

- [ ] **Step 4: Run — expect PASS**

Run: `bin/rspec spec/jobs/prune_snapshots_job_spec.rb`

- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "feat: add PruneSnapshotsJob for daily cleanup"
```

---

## Task 14: SolidQueue recurring schedule

**Files:**
- Create: `config/recurring.yml`

- [ ] **Step 1: Write schedule**

Create `config/recurring.yml`:
```yaml
production:
  fetch_feeds_frequent:
    class: FetchFeedsJob
    schedule: "every 5 minutes"
    args: ["frequent"]
  fetch_feeds_full:
    class: FetchFeedsJob
    schedule: "every 30 minutes"
    args: ["full"]
  prune_snapshots:
    class: PruneSnapshotsJob
    schedule: "every day at 3am"

development:
  fetch_feeds_frequent:
    class: FetchFeedsJob
    schedule: "every 5 minutes"
    args: ["frequent"]
  fetch_feeds_full:
    class: FetchFeedsJob
    schedule: "every 30 minutes"
    args: ["full"]
```

- [ ] **Step 2: Verify scheduler loads config**

Start the scheduler locally in a scratch terminal:
```bash
bin/jobs start --recurring-schedule-file=config/recurring.yml
```
Expected: log shows "scheduling fetch_feeds_frequent" etc. Stop with Ctrl-C.

- [ ] **Step 3: Update Kamal scheduler cmd**

Confirm `config/deploy.yml` scheduler server has `cmd: bin/jobs start --recurring-schedule-file=config/recurring.yml` (added in Plan 1 Task 14).

- [ ] **Step 4: Commit**

```bash
git add config/recurring.yml
git commit -m "chore: configure solid_queue recurring schedules"
```

---

## Task 15: Dashboard — show matches

**Files:**
- Modify: `app/controllers/dashboard_controller.rb`
- Modify: `app/frontend/pages/dashboard/index.tsx`
- Modify: `spec/requests/dashboard_spec.rb`

- [ ] **Step 1: Expand failing spec**

Edit `spec/requests/dashboard_spec.rb`. Replace the authenticated block with:
```ruby
    context "authenticated" do
      let(:user) { create(:user) }
      before { sign_in user }

      it "renders matches for topics this user subscribes to, sorted by matched_at desc" do
        subscribed = create(:topic)
        unsubscribed = create(:topic)
        create(:topic_subscription, user: user, topic: subscribed)

        older = create(:match, topic: subscribed, matched_at: 2.hours.ago, reason: "Older match")
        newer = create(:match, topic: subscribed, matched_at: 10.minutes.ago, reason: "Newer match")
        _hidden = create(:match, topic: subscribed, dismissed_at: Time.current, reason: "Hidden")
        _not_subscribed = create(:match, topic: unsubscribed, reason: "Not subscribed")

        get "/"

        body = response.body
        expect(body).to include("dashboard/index")
        # newer should appear before older in the JSON props
        expect(body.index("Newer match")).to be < body.index("Older match")
        expect(body).not_to include("Hidden")
        expect(body).not_to include("Not subscribed")
      end
    end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/dashboard_spec.rb`

- [ ] **Step 3: Controller**

Edit `app/controllers/dashboard_controller.rb`:
```ruby
class DashboardController < ApplicationController
  def index
    subscribed_topic_ids = current_user.subscribed_topics.select(:id)
    matches = Match.visible
                   .where(topic_id: subscribed_topic_ids)
                   .includes(:story, :topic)
                   .recent
                   .limit(100)

    render inertia: "dashboard/index", props: {
      matches: matches.map { |m| match_props(m) }
    }
  end

  private

  def match_props(match)
    {
      id: match.id,
      topic: { id: match.topic.id, name: match.topic.name },
      story: {
        id: match.story.id,
        hn_id: match.story.hn_id,
        title: match.story.title,
        url: match.story.url,
        score: match.story.score,
        descendants: match.story.descendants,
        hn_url: "https://news.ycombinator.com/item?id=#{match.story.hn_id}",
      },
      relevance_score: match.relevance_score.to_f,
      velocity_score: match.velocity_score&.to_f,
      reason: match.reason,
      matched_at: match.matched_at.iso8601,
    }
  end
end
```

- [ ] **Step 4: Dashboard page**

Replace `app/frontend/pages/dashboard/index.tsx`:
```tsx
import { Head, router } from "@inertiajs/react";

type Match = {
  id: number;
  topic: { id: number; name: string };
  story: {
    id: number;
    hn_id: number;
    title: string;
    url: string | null;
    score: number;
    descendants: number;
    hn_url: string;
  };
  relevance_score: number;
  velocity_score: number | null;
  reason: string;
  matched_at: string;
};

export default function Index({ matches }: { matches: Match[] }) {
  const markPosted = (id: number) =>
    router.post(`/matches/${id}/mark_posted`, {}, { preserveScroll: true });
  const dismiss = (id: number) =>
    router.post(`/matches/${id}/dismiss`, {}, { preserveScroll: true });

  return (
    <>
      <Head title="Dashboard" />
      <h1 className="text-2xl font-semibold mb-4">Climbing HN stories</h1>
      {matches.length === 0 ? (
        <p className="text-gray-600">No matches yet. Check back in a few minutes.</p>
      ) : (
        <ul className="space-y-3">
          {matches.map((m) => (
            <li key={m.id} className="bg-white rounded border border-gray-200 p-4">
              <div className="flex justify-between items-start gap-4">
                <div className="flex-1">
                  <div className="text-xs text-gray-500 mb-1">
                    <span className="font-medium text-gray-700">{m.topic.name}</span>
                    <span className="mx-1">·</span>
                    {new Date(m.matched_at).toLocaleString()}
                    {m.velocity_score !== null && (
                      <>
                        <span className="mx-1">·</span>
                        <span>+{m.velocity_score.toFixed(1)} pts/hr</span>
                      </>
                    )}
                  </div>
                  <a
                    href={m.story.url || m.story.hn_url}
                    target="_blank"
                    rel="noreferrer"
                    className="text-lg font-medium text-blue-700 hover:underline"
                  >
                    {m.story.title}
                  </a>
                  <div className="text-sm text-gray-500 mt-1">
                    {m.story.score} points · {m.story.descendants} comments ·{" "}
                    <a href={m.story.hn_url} target="_blank" rel="noreferrer" className="underline">
                      HN thread
                    </a>
                  </div>
                  <p className="text-sm text-gray-700 mt-2 italic">{m.reason}</p>
                </div>
                <div className="flex flex-col gap-1 text-xs">
                  <button
                    onClick={() => markPosted(m.id)}
                    className="bg-green-600 text-white px-2 py-1 rounded"
                  >
                    Mark as posted
                  </button>
                  <button
                    onClick={() => dismiss(m.id)}
                    className="bg-gray-200 text-gray-800 px-2 py-1 rounded"
                  >
                    Dismiss
                  </button>
                </div>
              </div>
            </li>
          ))}
        </ul>
      )}
    </>
  );
}
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rspec spec/requests/dashboard_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: dashboard shows matches for user's subscribed topics"
```

---

## Task 16: MatchesController — dismiss + mark_as_posted

**Files:**
- Create: `app/controllers/matches_controller.rb`
- Modify: `config/routes.rb`
- Create: `spec/requests/matches_spec.rb`

- [ ] **Step 1: Spec**

Create `spec/requests/matches_spec.rb`:
```ruby
require "rails_helper"

RSpec.describe "Matches", type: :request do
  let(:user) { create(:user) }
  let(:topic) { create(:topic) }
  let!(:subscription) { create(:topic_subscription, user: user, topic: topic) }
  let(:match) { create(:match, topic: topic) }

  before { sign_in user }

  describe "POST /matches/:id/mark_posted" do
    it "sets posted_at and redirects to dashboard" do
      post "/matches/#{match.id}/mark_posted"
      expect(match.reload.posted_at).to be_present
      expect(response).to redirect_to(root_path)
    end

    it "404s for a match on a topic the user is not subscribed to" do
      other_topic = create(:topic)
      other = create(:match, topic: other_topic)
      expect { post "/matches/#{other.id}/mark_posted" }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "POST /matches/:id/dismiss" do
    it "sets dismissed_at" do
      post "/matches/#{match.id}/dismiss"
      expect(match.reload.dismissed_at).to be_present
    end
  end
end
```

- [ ] **Step 2: Run — expect FAIL**

Run: `bin/rspec spec/requests/matches_spec.rb`

- [ ] **Step 3: Routes**

Edit `config/routes.rb` — extend the existing route file (which already has the topics + admin blocks from Plan 1 Task 9):
```ruby
Rails.application.routes.draw do
  devise_for :users
  root to: "dashboard#index"

  resources :topics, only: [:index] do
    resource :subscription, only: [:create, :update, :destroy],
                            controller: "topic_subscriptions"
  end

  namespace :admin do
    root "topics#index"
    resources :topics, except: [:destroy, :show]
  end

  post "matches/:id/mark_posted", to: "matches#mark_posted", as: :mark_posted_match
  post "matches/:id/dismiss", to: "matches#dismiss", as: :dismiss_match

  get "up" => "rails/health#show", as: :rails_health_check
end
```

- [ ] **Step 4: Controller**

Create `app/controllers/matches_controller.rb`:
```ruby
class MatchesController < ApplicationController
  before_action :set_match

  def mark_posted
    @match.update!(posted_at: Time.current)
    redirect_to root_path, notice: "Marked as posted."
  end

  def dismiss
    @match.update!(dismissed_at: Time.current)
    redirect_to root_path, notice: "Dismissed."
  end

  private

  def set_match
    # Only matches on topics the current user is subscribed to.
    @match = Match.joins(topic: :topic_subscriptions)
                  .where(topic_subscriptions: { user_id: current_user.id })
                  .find(params[:id])
  end
end
```

- [ ] **Step 5: Run — expect PASS**

Run: `bin/rspec spec/requests/matches_spec.rb`

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "feat: add matches#mark_posted and matches#dismiss"
```

---

## Task 17: End-to-end manual verification

**Files:** none (manual)

- [ ] **Step 1: Full test suite green**

Run: `bin/rspec`
Expected: all specs PASS.

- [ ] **Step 2: Prime the app**

```bash
bin/rails db:seed   # from Plan 1 seeds
bin/rails server    # terminal 1
bin/vite dev        # terminal 2
bin/jobs start --recurring-schedule-file=config/recurring.yml  # terminal 3
```

- [ ] **Step 3: Observe**

- Sign in as `dev@example.com / password123`.
- Visit `/`. Initially empty. Wait 5–15 minutes (first poll plus classification).
- Expect to see matches appear on dashboard (if any HN stories match the seed topics "AI agents" or "Rust").
- Click **Mark as posted** → match disappears.
- Check `StorySnapshot.count` in Rails console — should be growing.
- Check `Story.active.count` and `Story.archived.count` — stories should gradually shift to archived.

- [ ] **Step 4: Commit any config tweaks found**

If thresholds need adjustment based on real-world observation, edit `config/tracking.yml` and commit.

```bash
git add config/tracking.yml
git commit -m "tune: adjust tracking thresholds after manual observation"
```

---

## Plan 2 Done — State of the Application

At the end of Plan 2:

- HN poller runs on schedule and populates `stories` and `story_snapshots`.
- Stories archive themselves via the 3 archival rules (72h cutoff, cooling, flat).
- New topic creation triggers a backfill against the last 24 h of stories.
- Keyword prefilter + OpenAI classification produces `Match` rows.
- Dashboard shows a live list of climbing stories matching the user's topics.
- Mark-as-posted and dismiss actions work.
- Daily classification budget prevents cost runaway.
- Snapshot pruning keeps table bounded.

What's still missing (→ Plan 3):
- Actual notification delivery. `NotifyJob` exists as a stub but doesn't deliver anything yet.
- Web Push (VAPID + service worker + subscribe UI).
- Discord webhook POSTing.
- Failure surfacing in topic settings.
