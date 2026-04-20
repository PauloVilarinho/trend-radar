import { createInertiaApp } from "@inertiajs/react"
import { createRoot } from "react-dom/client"
import type { ReactNode, FC } from "react"
import AppLayout from "../layouts/AppLayout"

type PageModule = { default: FC & { layout?: (node: ReactNode) => ReactNode } }

void createInertiaApp({
  resolve: (name) => {
    const pages = import.meta.glob<PageModule>("../pages/**/*.tsx", { eager: true })
    const page = pages[`../pages/${name}.tsx`]
    page.default.layout ||= (pageNode) => <AppLayout>{pageNode}</AppLayout>
    return page
  },
  setup({ el, App, props }) {
    createRoot(el).render(<App {...props} />)
  },
}).catch((error) => {
  if (document.getElementById("app")) {
    throw error
  } else {
    console.error(
      "Missing root element.\n\n" +
      "If you see this error, it probably means you loaded Inertia.js on non-Inertia pages.",
    )
  }
})
