# Trend Radar — HN Trend Monitor (MVP Design)

**Date:** 2026-04-17 (amended 2026-04-20)
**Status:** Design approved, awaiting implementation plan
**Scope:** MVP — Hacker News only. Twitter and Reddit are explicitly out of scope for this spec.

**2026-04-20 amendment:** topics became a shared, admin-curated catalog; users subscribe instead of owning their own topic rows. Driver: OpenAI classification cost scales with unique topics, not users × topics, so sharing collapses N overlapping subscriptions into one classify call. Touches: `topics` table (drops `user_id`, `discord_webhook`), new `topic_subscriptions` join table, `users.admin` boolean, new `/admin/topics` namespace, `MatchJob` + `NotifyJob` pipeline.

## Purpose

A multi-user web application that monitors Hacker News for stories matching a shared catalog of topics, detects when those stories are gaining traction fast (velocity), and notifies subscribers via web push and per-subscription Discord webhooks so editorial/social-media teams can post about trending tech topics quickly. Topics are curated by admins; any signed-in user can subscribe to them.

## Key Decisions

| Decision | Choice |
|---|---|
| Product shape | Multi-user web product |
| Data source (MVP) | Hacker News public API (free, no key) |
| Trend signal | Velocity rate check + keyword/topic match (combination) |
| Velocity model | Simple rate check (points/hour between snapshots) + poll young stories every 5 min, others every 30 min |
| Topic matching | Hybrid: keyword prefilter → OpenAI `gpt-4o-mini` classification |
| LLM provider | OpenAI |
| Notifications | In-app dashboard + Web Push + per-topic Discord webhooks |
| Stack | Rails 8 + Inertia + React, PostgreSQL, SolidQueue |
| Auth | Devise with plain ERB auth views; Inertia/React for the rest |
| Deployment | Kamal on a single VPS |

## MVP Scope

**In scope:**
1. User sign up / log in (Devise); admin role gated by `users.admin` boolean
2. Admin catalog of topics (keyword lists); regular users subscribe and optionally attach their own Discord webhook per subscription
3. HN poller (every 30 min, young stories every 5 min)
4. Keyword prefilter → OpenAI classification → velocity check pipeline
5. In-app dashboard showing matched + climbing stories
6. Web push notifications (per-user opt-in)
7. Discord webhook notifications (per-topic)
8. "Mark as posted" / "Dismiss" actions on matches
9. History of past alerts (last 7 days)

**Explicitly out of scope for MVP:**
- Twitter / Reddit sources
- Admin / usage dashboard
- Billing / plans
- Mobile app / mobile push

## Architecture

Single Rails 8 app deployed to a single VPS via Kamal, running three process types against one PostgreSQL database:

```
┌──────────────────────────────────────────────────────────────────┐
│                      VPS (Kamal deploy)                          │
│                                                                  │
│  ┌────────────┐   ┌──────────────────┐   ┌────────────────┐      │
│  │  web       │   │  worker          │   │  scheduler     │      │
│  │  (Puma)    │   │  (SolidQueue)    │   │  (SolidQueue   │      │
│  │            │   │                  │   │   recurring)   │      │
│  │  Rails +   │   │  Runs:           │   │  Enqueues:     │      │
│  │  Inertia/  │   │  - FetchFeedsJob │   │  - every 5 min │      │
│  │  React +   │   │  - FetchStoryJob │   │    (young)     │      │
│  │  Devise    │   │  - MatchJob      │   │  - every 30 min│      │
│  │            │   │  - NotifyJob     │   │    (full top)  │      │
│  │            │   │  - PruneSnapshotsJob (daily)          │      │
│  └─────┬──────┘   └─────────┬────────┘   └────────┬───────┘      │
│        │                    │                     │              │
│        └────────────┬───────┴─────────────────────┘              │
│                     │                                            │
│              ┌──────▼────────┐                                   │
│              │  PostgreSQL   │ ← everything (app data +          │
│              │               │   SolidQueue jobs)                │
│              └───────────────┘                                   │
└──────────────────────────────────────────────────────────────────┘
        │                                     │
        ▼                                     ▼
  ┌─────────────────┐                  ┌──────────────┐
  │ Hacker News API │                  │ OpenAI API   │
  │ (HTTPS JSON)    │                  │ (gpt-4o-mini)│
  └─────────────────┘                  └──────────────┘

  Outbound notifications:
  - Web Push (VAPID) → user browsers
  - Discord webhooks → user-configured URLs
```

No Redis, no external job queue. SolidQueue uses Postgres.

## Data Model

### `users` (Devise standard + admin flag)
Email, encrypted password, timestamps, plus `admin` boolean (default `false`, `null: false`). Bootstrap the first admin via `rake admin:promote[email@example.com]`; dev/test `db/seeds.rb` creates an admin user with a known password for reachable admin UI.

### `topics`
Shared catalog of topics curated by admins. Regular users cannot create, edit, or destroy topics — only subscribe.

| Column | Type | Notes |
|---|---|---|
| `created_by_id` | fk users, nullable | Audit: which admin added this. `on_delete: nullify`. |
| `name` | string | e.g., "AI agents"; unique globally (case-insensitive). |
| `keywords` | text[] | Prefilter terms, ≥1, ≤20 |
| `active` | boolean, default true | Admin soft-disable lever. No destroy action in MVP — inactive topics are skipped by the pipeline. |
| timestamps | | |

Indexes: `LOWER(name)` unique.

Limits: ≤20 keywords per topic.

### `topic_subscriptions`
Per-user opt-in to a shared topic, carrying per-user settings.

| Column | Type | Notes |
|---|---|---|
| `user_id` | fk users | cascade delete |
| `topic_id` | fk topics | cascade delete |
| `discord_webhook` | string, encrypted, nullable | Each subscriber's own Discord destination. |
| `active` | boolean, default true | User pause without unsubscribing. |
| timestamps | | |

Indexes: `(user_id, topic_id)` unique.

Limits: ≤50 subscriptions per user (validation).

### `stories`
One row per HN item we've seen.

| Column | Type | Notes |
|---|---|---|
| `hn_id` | bigint | unique |
| `title` | string | |
| `url` | string, nullable | null for Ask HN |
| `by` | string | author |
| `score` | int | latest score |
| `descendants` | int | comment count |
| `story_type` | string | story/ask/show/job |
| `text` | text, nullable | Ask HN body |
| `hn_created_at` | datetime | |
| `first_seen_at` | datetime | |
| `last_polled_at` | datetime | |
| `tracking_status` | enum: `active` \| `archived`, default `active` | |
| `archived_at` | datetime, nullable | |

Indexes: `hn_id` unique, `last_polled_at`, partial on `tracking_status WHERE status='active'`.

### `story_snapshots`
Time-series score/comments for velocity.

| Column | Type | Notes |
|---|---|---|
| `story_id` | fk | |
| `score` | int | |
| `descendants` | int | |
| `captured_at` | datetime | |

Indexes: `(story_id, captured_at)`.

Retention: pruned to last 7 days by `PruneSnapshotsJob`.

### `matches`
Junction of story × topic, produced when keyword prefilter + LLM confirm relevance.

| Column | Type | Notes |
|---|---|---|
| `story_id` | fk | |
| `topic_id` | fk | |
| `relevance_score` | decimal | LLM 0–1 |
| `reason` | text | "Why this matters" — becomes post starter |
| `velocity_score` | decimal | points/hour at match time |
| `matched_at` | datetime | |
| `dismissed_at` | datetime, nullable | User clicked Dismiss |
| `posted_at` | datetime, nullable | User clicked Mark as posted |

Indexes: `(story_id, topic_id)` unique; `(topic_id, matched_at DESC)` for dashboard queries.

### `notifications`
Audit log per delivery, idempotency guard. With shared topics, one match fans out to many subscribers, so uniqueness must include the delivery target.

| Column | Type | Notes |
|---|---|---|
| `match_id` | fk | |
| `channel` | enum: `web_push` \| `discord` | |
| `target_type` | string | `"PushSubscription"` or `"TopicSubscription"` |
| `target_id` | bigint | id of the delivery target (push_subscription or topic_subscription) |
| `status` | enum: `pending` \| `sent` \| `failed` | |
| `sent_at` | datetime, nullable | |
| `error` | text, nullable | |

Indexes: `(match_id, channel, target_type, target_id)` unique — prevents double-send to the same browser or the same subscription's Discord channel on retry.

### `push_subscriptions`
Per-browser Web Push endpoints.

| Column | Type | Notes |
|---|---|---|
| `user_id` | fk | |
| `endpoint` | string | |
| `p256dh_key` | string | |
| `auth_key` | string | |
| `user_agent` | string, nullable | for display |
| timestamps | | |

## Relationships

- `User` has_many `topic_subscriptions`, `push_subscriptions`; has_many `subscribed_topics, through: :topic_subscriptions, source: :topic`; has_many `created_topics, class_name: "Topic", foreign_key: :created_by_id, dependent: :nullify`
- `Topic` belongs_to `created_by, class_name: "User", optional: true`; has_many `topic_subscriptions`, `matches`; has_many `subscribers, through: :topic_subscriptions, source: :user`
- `TopicSubscription` belongs_to `user`, `topic`
- `Story` has_many `story_snapshots`, `matches`
- `Match` has_many `notifications` (one per (channel, target))

## Routes & Access

```ruby
devise_for :users
root "dashboard#index"

resources :topics, only: [:index] do
  resource :subscription, only: [:create, :update, :destroy],
                          controller: "topic_subscriptions"
end

namespace :admin do
  root "topics#index"
  resources :topics, except: [:destroy, :show]  # soft-disable via update
end
```

- **Regular users** can only `GET /topics` (the catalog) and manage their own subscription under `/topics/:topic_id/subscription`.
- **Admins** reach full topic CRUD (minus destroy) under `/admin/topics`. A single `ApplicationController#require_admin!` before-action gates the admin namespace; non-admins are redirected to root with an "Admins only." flash.
- **AppLayout** renders an "Admin" nav link only when `current_user.admin`.

## Data Flow (Lifecycle of a Story)

Five pipeline stages. Each is its own job class for testability and retry isolation.

### Stage 1 — `FetchFeedsJob` (the poller)

SolidQueue recurring schedules:
- Every **5 min** → `/newstories.json` + `/topstories.json`
- Every **30 min** → additionally `/beststories.json`

Logic:
1. GET the feed(s), receive array of item IDs.
2. Diff against `stories.hn_id` — enqueue `FetchStoryJob` for any new IDs.
3. For existing stories that are "young" (age < 6 h) OR whose `last_polled_at` is stale relative to their schedule, enqueue `FetchStoryJob`.
4. Skip stories with `tracking_status = 'archived'`.

### Stage 2 — `FetchStoryJob(hn_id)`

1. GET `/item/{id}.json`.
2. Upsert into `stories`, update `last_polled_at`.
3. Insert a `story_snapshots` row (score + descendants + timestamp).
4. Compute rolling velocity from last 3 snapshots (`points_gained / elapsed_hours`).
5. Apply archival rules. Archive (set `tracking_status='archived'`, `archived_at=now`) if ANY of:
   - `age > 72h` (hard cutoff)
   - `age > 12h` AND last 3 rolling velocities all `< 3 pts/hr`
   - 3 consecutive snapshots with identical score and identical comment count
6. Decide if this story is a **match candidate**:
   - New story (first time) → always candidate
   - Existing story → candidate if velocity crosses threshold (MVP default: +15 points/hour with ≥30 total)
7. If candidate and not archived → enqueue `MatchJob(story_id)`.

### Stage 3 — `MatchJob(story_id)` — keyword prefilter + LLM

**Classification is per (story, topic), not per user.** A topic with 100 subscribers is classified once; all 100 subscribers get fan-out notifications off the single `Match` row.

1. Load the story.
2. Query all `active: true` topics whose any `keywords` entry appears in `story.title` OR `story.url` OR `story.text` (case-insensitive, using Postgres array semantics + `ILIKE` with escaped literals). No user-scoping — the topic catalog is shared.
3. For each matching topic **without an existing `Match` for this story**, call OpenAI:
   - Model: `gpt-4o-mini`
   - `response_format: json_object`
   - Prompt: topic name + keywords + story (title, URL, text snippet), asking for `{score: float 0-1, reason: string}`.
4. **Invalid JSON handling (inline retry loop):**
   - Parse the response; require both `score` and `reason` keys.
   - On parse failure or missing keys → retry up to 3 times with a corrective system message: "Your previous response was not valid JSON. Respond with ONLY a JSON object with keys 'score' and 'reason'."
   - After 3 retries, record `relevance_score=0`, do not create a Match, log the last raw response, move on.
5. If `score >= 0.6` (tunable) → insert `Match` row with `relevance_score`, `reason`, `velocity_score`.
6. For each new Match → enqueue `NotifyJob(match_id)`.

Cost-control soft guard: if today's classification count exceeds a configurable budget (default 500/day), stop enqueuing new MatchJobs and log a warning.

### Stage 4 — `NotifyJob(match_id)` — fan-out to subscribers

1. Load the match + its topic + all `topic_subscriptions` where `active: true`, preloading each subscriber's `push_subscriptions`.
2. For each active subscription:
   - **Web push** → for each of the subscriber's `push_subscriptions`, send via `web-push` gem. One `notifications` row per `(match_id, channel: :web_push, target: push_subscription)`.
   - **Discord** → if `subscription.discord_webhook` is present, POST to it. One `notifications` row per `(match_id, channel: :discord, target: topic_subscription)`.
3. Idempotency guard: `(match_id, channel, target_type, target_id)` unique constraint prevents double-send on retry.
4. On failure: update notification `status=failed`, `error=...`. Log; do not refan.

### Stage 5 — User action (controller, no job)

- `POST /matches/:id/mark_posted` → sets `posted_at`
- `POST /matches/:id/dismiss` → sets `dismissed_at`
- Dashboard filters dismissed/posted out by default, with a "show all" toggle.

### Supporting: `PruneSnapshotsJob` (daily)

Delete `story_snapshots` where `captured_at < 7 days ago`.

### Supporting: `BackfillSubscriptionJob(topic_subscription_id)`

When a user subscribes to an existing topic, run MatchJob logic against the last ~24 h of stories (or reuse existing `Match` rows for that topic) so the new subscriber's dashboard isn't empty. When an admin creates a brand-new topic, no backfill is needed — there are no subscribers yet; `BackfillSubscriptionJob` fires the first time someone subscribes.

## Error Handling & Edge Cases

### HN API failures
- **Timeouts / 5xx:** SolidQueue retries with exponential backoff (5 attempts). Next scheduled poll naturally recovers missed IDs.
- **Deleted / dead stories:** HN returns `{"deleted": true}` / `{"dead": true}`. Skip; if already stored, archive.
- **Malformed JSON / schema drift:** rescue `JSON::ParserError`, skip missing required fields, log.
- **HN outage:** pipeline resumes on recovery. Velocity math uses actual `captured_at` timestamps, so gaps are handled.

### OpenAI failures
- **Rate limits (429):** SolidQueue retry with backoff.
- **Invalid JSON response:** inline retry loop (up to 3 attempts per call) with a corrective message; after 3 → treat as no match.
- **API outage:** jobs pile up and drain when API recovers. Dashboard stays live.
- **Cost runaway:** daily classification soft budget.

### Discord webhook failures
- **Bad URL / revoked:** 4xx → mark `notifications.status=failed`, do not retry. Surface the last failure on the subscription row (visible to the owning user on their topics page).
- **Rate limit (429):** retry respecting `Retry-After`.
- **Discord outage:** retry a few times, then fail.

### Web Push failures
- **Expired / invalid subscription (404/410):** delete the `push_subscriptions` row.
- **VAPID keys:** stored in Rails credentials. Rotation invalidates all subs; users re-opt-in.

### Race conditions
- **Concurrent story fetch:** `hn_id` unique + `INSERT … ON CONFLICT DO UPDATE`.
- **Duplicate match:** `(story_id, topic_id)` unique; rescue `RecordNotUnique`.
- **Duplicate notification:** `(match_id, channel, target_type, target_id)` unique.
- **Concurrent subscribe:** `(user_id, topic_id)` unique on `topic_subscriptions`.

### User-input edge cases
- **Keyword with SQL special chars:** parameter-bound `ILIKE`, escape `%` and `_` as literals.
- **Limits:** ≤20 keywords per topic (admin-enforced); ≤50 subscriptions per user.
- **Discord webhook URL format:** validate format before saving (on `topic_subscriptions`).
- **Empty keyword list:** disallowed (validation requires ≥1).
- **Duplicate topic name:** enforced by `LOWER(name)` unique index; admin form surfaces the conflict.

### Deployment edge cases
- **First boot:** `FetchFeedsJob` discovers 500 top stories, enqueues 500 `FetchStoryJob`s, drains in minutes.
- **Scheduler restart mid-poll:** SolidQueue recurring schedules are idempotent per tick.
- **Clock skew:** velocity uses DB-stored `captured_at` deltas, not wall clock.

### Observability
- Structured logs per job: `story_hn_id`, `match_id`, `duration_ms`.
- `/health` endpoint on web process.
- Error reporting hooked to Sentry/Honeybadger (or Rails logs).

## Testing Strategy

**Stack:** RSpec + VCR + WebMock + Capybara (for one E2E).

### Unit tests
- `Topic` validations: keyword cap, ≥1 keyword, unique name (case-insensitive), name/keywords presence.
- `TopicSubscription` validations: webhook URL format, 50-subscription cap per user, unique `(user_id, topic_id)`.
- `Story.archive!` under each of the 3 archive conditions.
- `VelocityCalculator` service: rolling points/hour, edge cases (single snapshot → nil, gaps).
- `KeywordMatcher` service: case-insensitive, safe against SQL special chars, matches across title/url/text.

### Job tests (with stubs/mocks)
- `FetchFeedsJob`: WebMock HN feeds → correct IDs enqueued; archived stories skipped.
- `FetchStoryJob`: WebMock item endpoint → upsert + snapshot + archive decision + candidate detection.
- `MatchJob`: VCR-cassette OpenAI → (a) zero LLM calls when keyword prefilter fails, (b) LLM called per passing topic, (c) match only when `score ≥ 0.6`, (d) JSON retry loop up to 3× then graceful fail.
- `NotifyJob`: stub web-push gem + Discord webhook → idempotency verified, expired subscriptions deleted.

### Request specs
- Devise sign-up/login.
- `TopicsController#index` — catalog view with subscription state.
- `TopicSubscriptionsController` — subscribe, update (webhook / pause), unsubscribe; 50-per-user limit enforced.
- `Admin::TopicsController` — admin CRUD (no destroy); regular users redirected off admin routes.
- Dashboard: correct Inertia props; dismiss/mark-posted endpoints.
- Web Push subscribe/unsubscribe endpoints.

### System test
- One Capybara + headless Chrome happy path: admin signs in → creates topic → regular user signs up → subscribes → trigger fake matching story → dashboard shows match → mark as posted → removed from default view.

### External API handling
- VCR cassettes for OpenAI + HN, scrubbed of keys, committed to repo. No real external calls in CI.

### Manual verification (documented, not automated)
- Web Push in Chrome/Firefox/Safari.
- Discord webhook posting to a test channel.
- Archival thresholds against real HN data; tune in staging.

### Priority order for MVP test writing
1. Model validations
2. `MatchJob` with VCR (highest-risk path)
3. `FetchStoryJob` + archive decision
4. Dashboard request specs
5. Everything else fills in as edges are hit

## Configuration

`config/tracking.yml` (tunable without migration):
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

Secrets (Rails credentials):
- `openai.api_key`
- `web_push.vapid_public_key`, `web_push.vapid_private_key`, `web_push.subject`

## Open Questions / Deferred

- Exact Devise configuration (confirmations? lockable?) — decide during implementation.
- Rate-limiting the web UI (per-user) — probably overkill for MVP, revisit if abused.
- Frontend styling system (Tailwind vs CSS modules vs other) — decide during implementation.
- Multi-source architecture for future Twitter/Reddit sources: the `stories` table is HN-specific today; when adding sources, introduce a `source` column and polymorphic adapter pattern. Out of scope now.
