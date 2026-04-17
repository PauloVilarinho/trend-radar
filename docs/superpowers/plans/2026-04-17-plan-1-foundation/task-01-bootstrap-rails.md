# Task 1 — Bootstrap Rails 8 application

**Status:** ✅ DONE
**Commit:** `05aa5d3` — "chore: bootstrap Rails 8 app with postgres, tailwind, vite"

## What was done

1. `gem install rails -v "~> 8.0.0"` → installed Rails **8.0.5** (pinned via `rails _8.0.5_` because system already had 8.1.3).
2. `rails _8.0.5_ new . --database=postgresql --css=tailwind --skip-javascript --force` (note: `--javascript=vite` is invalid for Rails 8; only `importmap|bun|webpack|esbuild|rollup` are accepted).
3. `bundle add vite_rails` then `bundle exec vite install` to get Vite.
4. Vite's installer fell back to `pnpm add -D vite @vitejs/plugin-legacy vite-plugin-ruby` because **npm is blocked** on this machine. `pnpm-lock.yaml` is the authoritative JS lockfile going forward.
5. `bin/rails db:create` created `trend_radar_development` and `trend_radar_test`. No `config/database.yml` changes needed — default socket + OS user works on local PG 14.
6. Boot verified: `bin/rails server` booted on :3000, `curl` returned HTTP 200 with the Rails welcome page.
7. `git add -A && git commit -m "chore: bootstrap Rails 8 app with postgres, tailwind, vite"`.

## Files / structure produced

- `Gemfile`, `Gemfile.lock` — Rails 8.0.5 + standard Rails 8 gems + `vite_rails`.
- Full Rails app skeleton under `app/`, `config/`, `db/`, `bin/`, `public/`, `lib/`.
- `vite.config.ts`, `config/vite.json`, `package.json`, `pnpm-lock.yaml`.
- `app/assets/tailwind/application.css`, `Procfile.dev`, `bin/dev`.
- `Dockerfile`, `.dockerignore`, `.kamal/`, `config/deploy.yml` — generated but **inert** (not used this session).
- `.ruby-version` = `ruby-4.0.2`.
- Pre-existing `docs/` and `CLAUDE.md` preserved.

## Deviations from master plan (carry forward)

- `--javascript=vite` is not a valid Rails 8 flag → documented in the README.
- **npm is blocked** → pnpm is the JS package manager for this repo. Affects Task 15 (CI).
- **Ruby 4.0.2** (not 3.3). Rails 8.0.5 and all planned gems work on it; if a gem refuses to install on 4.0 during a future task, escalate.
