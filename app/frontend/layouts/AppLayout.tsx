import type { ReactNode } from "react"
import { Link, usePage } from "@inertiajs/react"

type PageProps = {
  current_user: { id: number; email: string; admin: boolean } | null
  flash: { notice?: string; alert?: string }
}

export default function AppLayout({ children }: { children: ReactNode }) {
  const { current_user, flash } = usePage<PageProps>().props

  return (
    <div className="min-h-screen bg-gray-50">
      <header className="bg-white border-b border-gray-200">
        <div className="mx-auto max-w-6xl px-4 py-3 flex justify-between items-center">
          <Link href="/" className="font-semibold text-lg">Trend Radar</Link>
          <nav className="flex gap-4 text-sm">
            {current_user ? (
              <>
                <Link href="/topics">Topics</Link>
                {current_user.admin && <Link href="/admin/topics">Admin</Link>}
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
  )
}
