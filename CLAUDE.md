# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project conventions

- **Extract services for complex logic.** When a method grows beyond simple model concerns or a controller action does more than read params and render, extract the logic to `app/services/`. Prefer pure functions where possible.
- **Controllers stay slim.** An action should read params, call one service or model method, and render. No business logic, no multi-step orchestration, no external API calls inline.
- **Run tests and the linter after every change.** After applying changes, run `bin/rspec` (scope to affected files during iteration, full suite before commit) and `bundle exec rubocop`. Do not claim a task is complete without green output.
