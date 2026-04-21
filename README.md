# trend-radar

A Rails 8 service that monitors Hacker News for stories matching a shared catalog of topics, detects when those stories are gaining traction fast, and notifies subscribers via web push and Discord webhooks.

Built as the working codebase for an ongoing experiment in measuring AI-generated code with objective quality gates — see [docs/blog/stop-reading-ai-code.md](docs/blog/stop-reading-ai-code.md).

## What it does

- **Shared topic catalog.** Admins curate topics with keyword lists; any signed-in user can subscribe.
- **HN ingestion.** Polls the Hacker News API on an interval (young stories every 5 min, others every 30 min).
- **Keyword + LLM matching.** Candidate stories are keyword-prefiltered, then passed to OpenAI `gpt-4o-mini` for classification.
- **Velocity check.** Matches are only surfaced once they cross a points-per-hour threshold.
- **Notifications.** In-app dashboard, web push (per user), and Discord webhooks (per subscription).

Full design: [`docs/superpowers/specs/2026-04-17-hn-trend-monitor-design.md`](docs/superpowers/specs/2026-04-17-hn-trend-monitor-design.md)

## Status

Work in progress. The topic catalog, subscription flow, and admin CRUD are implemented. Ingestion, classification, and notification delivery are in planning (see `docs/superpowers/plans/`).

## Tech stack

- **Rails 8** with Propshaft, Solid Cache / Queue / Cable
- **PostgreSQL**
- **Devise** for authentication; `users.admin` boolean for admin gating
- **Inertia + React + Vite** for the non-auth frontend (Tailwind for styling)
- **RSpec** + FactoryBot + Faker for tests
- **OpenAI** `gpt-4o-mini` for topic classification (planned)
- **Kamal** for deploys (planned)

## Setup

Prerequisites:
- Ruby 4.0.2 (a `.ruby-version` file is checked in)
- Node.js 20+ and `pnpm`
- PostgreSQL 14+
- `foreman` (`gem install foreman` if not on PATH)

```bash
# Clone and install dependencies
git clone <this-repo>
cd trend-radar
bundle install
pnpm install

# Set up the database
bin/rails db:prepare
bin/rails db:seed   # creates admin + sample user + a few topics

# Configure env vars (copy .env.example if present, or create .env)
# Required:
#   OPENAI_API_KEY=sk-...      (for topic classification; optional until ingestion lands)

# Run all dev processes (Rails, Vite, Tailwind watcher) via foreman
bin/dev
```

The seeded users are:

| Role | Email | Password |
|---|---|---|
| Admin | `admin@example.com` | `password123` |
| User | `user@example.com` | `password123` |

## Running tests

```bash
# Full suite
bin/rspec

# A single file
bin/rspec spec/models/topic_spec.rb

# Linter
bundle exec rubocop
```

## Quality gate

Every change — human or AI — has to clear a threshold gate before it can be considered done:

```bash
bin/rake quality
```

Runs the full spec suite with coverage, RuboCop Metrics cops, RubyCritic, Flog, and Mutant (mutation testing). Fails non-zero if any threshold is breached. Thresholds live in [`config/quality_thresholds.yml`](config/quality_thresholds.yml).

Expected output (green run):

```
Quality gates
=============

Line coverage             96.6%   >= 95.0%    ✓
Branch coverage           91.1%   >= 90.0%    ✓
Flog max (method)         19.8    <= 20       ✓
Flog max (class)          66.8    <= 70       ✓
Mutation kill ratio       69.6%   >= 69.5%    ✓

5/5 gates passed.
```

See the blog post for the reasoning behind each gate.

## Project structure

```
app/
  controllers/         # Rails controllers (admin namespace for curation)
  models/              # Topic, User, TopicSubscription, PushSubscription
  services/            # Extracted service objects (TopicIndexProps, etc.)
  frontend/            # React / Inertia pages
config/
  quality_thresholds.yml   # Quality gate thresholds
lib/
  quality/             # Parsers + aggregator for the quality gate
  tasks/quality.rake   # The rake task wiring it together
docs/
  blog/                # Blog posts
  superpowers/         # Design specs and implementation plans
script/
  mutant_bootstrap.rb  # Eager-loads Rails so Mutant can find subjects
spec/                  # RSpec tests + fixtures
```

## Project conventions

Baseline conventions are documented in [`CLAUDE.md`](CLAUDE.md) — it's the file the AI pair reads, but the rules apply to humans too:

- Extract services for complex logic; controllers stay slim.
- Run `bin/rspec` and `bundle exec rubocop` after every change.
- Run `bin/rake quality` before declaring a task complete.
- Update `MUTANT_SUBJECTS` in `lib/tasks/quality.rake` when adding new top-level constants.

## License

MIT. See [LICENSE](LICENSE).
