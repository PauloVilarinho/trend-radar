# Task 5 — Configure TailwindCSS for Inertia pages

**Status:** pending
**Depends on:** Task 4.

## Files

- Modify: `config/tailwind.config.js` (or `tailwind.config.js`)

## Steps

1. Verify Tailwind is already wired (from `rails new --css=tailwind`): `app/assets/tailwind/application.css` exists and `app/views/layouts/application.html.erb` loads it via `stylesheet_link_tag "tailwind", ...`.

2. Extend `content:` in `tailwind.config.js` so utilities used in React files get emitted:
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

3. Visual smoke (optional): run `bin/rails server` and `bin/vite dev` in two terminals; confirm a Tailwind utility class on any page renders.

4. **Commit.**
   ```bash
   git add -A
   git commit -m "chore: configure tailwind to scan frontend/**"
   ```
