# Task 4 — Install and configure Inertia.js + React

**Status:** pending
**Depends on:** Task 3.

## Files

- Create: `app/frontend/entrypoints/application.tsx`, `app/frontend/Layouts/AppLayout.tsx`
- Modify: `app/views/layouts/application.html.erb` (Inertia root), `app/controllers/application_controller.rb`
- Create: `config/initializers/inertia_rails.rb` (if generator produces one)

## Steps

1. Install (uses pnpm under the hood since npm is blocked here):
   ```bash
   bin/rails generate inertia:install --framework=react --typescript --vite
   ```
   If the generator invokes `npm install` and fails, install the JS deps manually with pnpm:
   ```bash
   pnpm add @inertiajs/react react react-dom
   pnpm add -D typescript @vitejs/plugin-react @types/react @types/react-dom
   ```

2. Verify the generator's scaffolding: `app/frontend/entrypoints/application.tsx`, `app/frontend/pages/` exists (will rename), `vite.config.ts` has the React plugin, `package.json` has `react`, `react-dom`, `@inertiajs/react`.

3. Rename:
   ```bash
   git mv app/frontend/pages app/frontend/Pages
   mkdir -p app/frontend/Layouts
   ```

4. Create `app/frontend/Layouts/AppLayout.tsx`:
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
         {flash.notice && <div className="bg-green-50 text-green-800 px-4 py-2 text-sm">{flash.notice}</div>}
         {flash.alert && <div className="bg-red-50 text-red-800 px-4 py-2 text-sm">{flash.alert}</div>}
         <main className="mx-auto max-w-6xl px-4 py-6">{children}</main>
       </div>
     );
   }
   ```

5. Wire `AppLayout` as default in `app/frontend/entrypoints/application.tsx`. Replace the `resolve` function body:
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
   Keep the generator's existing imports for `createInertiaApp`, `createRoot`, `React`.

6. Replace `app/controllers/application_controller.rb`:
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

7. **Commit.**
   ```bash
   git add -A
   git commit -m "feat: configure inertia + react with shared AppLayout"
   ```
