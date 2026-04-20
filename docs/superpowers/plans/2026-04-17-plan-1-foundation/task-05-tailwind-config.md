# Task 5 — Configure TailwindCSS for Inertia pages + style Devise views

**Status:** pending
**Depends on:** Task 4.

**Environment deviation:** Project uses `tailwindcss-rails 4.4.0` which ships **Tailwind v4**. There is no `tailwind.config.js` — configuration lives in the CSS via `@import` / `@source` / `@theme` directives.

## Files

- Modify: `app/assets/tailwind/application.css` (add `@source` directives)
- Modify: `app/views/layouts/application.html.erb` (better default layout + flash)
- Rewrite with Tailwind: `app/views/devise/sessions/new.html.erb`, `app/views/devise/registrations/new.html.erb`, `app/views/devise/registrations/edit.html.erb`, `app/views/devise/passwords/new.html.erb`, `app/views/devise/passwords/edit.html.erb`, `app/views/devise/confirmations/new.html.erb`, `app/views/devise/unlocks/new.html.erb`, `app/views/devise/shared/_links.html.erb`, `app/views/devise/shared/_error_messages.html.erb`

## Steps

1. Verify Tailwind is already wired: `app/assets/tailwind/application.css` exists and the Rails layout loads it via `stylesheet_link_tag :app` (which includes the tailwind build). `bin/rails tailwindcss:watch` is in `Procfile.dev`.

2. Add `@source` directives to `app/assets/tailwind/application.css` so Tailwind scans both ERB views and the React frontend:
   ```css
   @import "tailwindcss";

   @source "../../frontend/**/*.{js,jsx,ts,tsx}";
   @source "../../views/**/*.{erb,html}";
   @source "../../helpers/**/*.rb";
   ```
   Paths are relative to the CSS file.

3. Update `app/views/layouts/application.html.erb` body to render flash notices and use a sensible container (Devise pages use this layout, not Inertia/AppLayout).

4. Rewrite every Devise view under `app/views/devise/` to use Tailwind utilities — consistent card design: centered `max-w-md` card with shadow, labelled fields with focus ring, indigo primary button.

5. Visual smoke: `bin/dev` → visit `/users/sign_in` and `/users/sign_up`, confirm styled form renders.

6. **Commit.** (user approval required per project convention)
