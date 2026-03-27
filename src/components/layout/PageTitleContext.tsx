import { createContext, useContext, useState, type ReactNode } from 'react'

/**
 * PageTitleContext — allows any page component to set the mobile App Bar title.
 *
 * Usage in a page:
 * ```tsx
 * import { usePageTitle } from '@/components/layout/PageTitleContext'
 *
 * export default function SalesOrdersPage() {
 *   usePageTitle('طلبات البيع')
 *   // ...
 * }
 * ```
 */

interface PageTitleContextValue {
  title: string
  setTitle: (title: string) => void
}

const PageTitleContext = createContext<PageTitleContextValue>({
  title: 'EDARA',
  setTitle: () => {},
})

export function PageTitleProvider({ children }: { children: ReactNode }) {
  const [title, setTitle] = useState('EDARA')
  return (
    <PageTitleContext.Provider value={{ title, setTitle }}>
      {children}
    </PageTitleContext.Provider>
  )
}

export function usePageTitle(title?: string) {
  const ctx = useContext(PageTitleContext)
  // If title is provided, set it on mount (via useEffect-like pattern via Context)
  if (title && ctx.title !== title) {
    ctx.setTitle(title)
  }
  return ctx
}

export default PageTitleContext
