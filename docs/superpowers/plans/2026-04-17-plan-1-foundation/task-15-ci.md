# Task 15 — CI pipeline (GitHub Actions)

**Status:** pending
**Depends on:** Task 13.

## Files

- Create: `.github/workflows/ci.yml`

## Deviation from master plan

The master plan uses `npm ci`. **npm is blocked on this dev machine and this repo uses pnpm** (`pnpm-lock.yaml` is the lockfile). The CI must use pnpm — either via `pnpm/action-setup@v4` or via `actions/setup-node@v4` with `cache: pnpm`.

## Steps

1. Create `.github/workflows/ci.yml`:
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
         - uses: pnpm/action-setup@v4
           with:
             version: 9
         - uses: actions/setup-node@v4
           with:
             node-version: 20
             cache: pnpm
         - run: pnpm install --frozen-lockfile
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

2. **Commit.**
   ```bash
   git add -A
   git commit -m "ci: add github actions workflow for rspec + vite build"
   ```

## Notes

- Ruby 4.0.2 locally is unusual. `ruby/setup-ruby@v1` reads `.ruby-version`; if GitHub Actions doesn't have a 4.0.2 build, we may need to pin `ruby-version: 3.3` in CI instead. If that happens, flag before the gem-install step fails the job.
- Postgres service uses 16 in CI (matches production target) even though local is 14.
