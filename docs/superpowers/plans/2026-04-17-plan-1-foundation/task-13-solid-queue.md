# Task 13 — SolidQueue setup

**Status:** pending
**Depends on:** Task 12.

## Files

- Modify: `config/database.yml` (queue DB entry — installer adds it), `config/application.rb`

## Steps

1. Install:
   ```bash
   bin/rails solid_queue:install
   bin/rails db:migrate
   ```
   This generates `db/queue_schema.rb` and the queue DB config.

2. Verify `config/database.yml` has a `queue` entry (installer adds it).

3. Set the Active Job adapter. Edit `config/application.rb` inside the `Application` class:
   ```ruby
   config.active_job.queue_adapter = :solid_queue
   ```

4. Smoke test (optional): `bin/rails console` →
   ```ruby
   class SmokeJob < ApplicationJob; def perform; Rails.logger.info("smoke"); end; end
   SmokeJob.perform_later
   ```
   In another terminal: `bin/jobs start`. Log should show "smoke". Stop with Ctrl-C, exit console.

5. **Commit.**
   ```bash
   git add -A
   git commit -m "chore: install solid_queue for background jobs"
   ```
