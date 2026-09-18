import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./WorkHubPage.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')
const workCssPath = fileURLToPath(new URL('./work.css', import.meta.url))
const workCss = readFileSync(workCssPath, 'utf8')

describe('WorkHubPage V2 source contract', () => {
  it('adopts the shared SegmentedControl with the exact Work mode order and labels', () => {
    expect(source).toContain("import SegmentedControl from '@/components/patterns/SegmentedControl'")
    expect(source).toContain("type HubMode = 'actions' | 'work' | 'attention'")

    const expectedItems = [
      "{ value: 'actions', label: 'مطلوب مني الآن' }",
      "{ value: 'work', label: 'كل الأعمال' }",
      "{ value: 'attention', label: 'يحتاج انتباه' }",
    ]
    const positions = expectedItems.map(item => source.indexOf(item))

    expect(positions.every(position => position >= 0)).toBe(true)
    expect(positions).toEqual([...positions].sort((a, b) => a - b))
    expect(source).toContain("const [mode, setMode] = useState<HubMode>('actions')")
    expect(source).toContain('value={mode}')
    expect(source).toContain('onValueChange={value => setMode(value as HubMode)}')
    expect(source).toContain('items={HUB_MODE_ITEMS}')
    expect(source).toContain('ariaLabel="نوع العرض"')
  })

  it('retires only the page-local selector renderer and its selector-specific CSS', () => {
    expect(source).not.toContain('className="work-segmented"')
    expect(workCss).not.toContain('.work-segmented')
    expect(source).toContain('<section className="work-toolbar" aria-label="تصفية الأعمال">')
    expect(source).toContain('className="work-search"')
    expect(workCss).toContain('.work-toolbar {')
    expect(workCss).toContain('.work-search {')
  })

  it('keeps Work query, filtering, summary-card and search ownership page-local', () => {
    expect(source).toContain('useMyActionInbox(100)')
    expect(source).toContain('useVisibleWorkItems({ limit: 150 })')
    expect(source).toContain('useOperationalFlags(itemIds)')
    expect(source).toContain("if (mode === 'attention')")
    expect(source).toContain('const filteredItems = useMemo(() => {')
    expect(source).toContain('const filteredActions = useMemo(() => {')
    expect(source).toContain("onClick={() => setMode('actions')}")
    expect(source).toContain("onClick={() => setMode('attention')}")
    expect(source).toContain('value={search}')
    expect(source).toContain('onChange={event => setSearch(event.target.value)}')
    expect(source).toContain('aria-label="البحث في الأعمال"')
  })

  it('does not move permission, request, routing or mobile-create semantics into the shared control', () => {
    expect(source).toContain("const canCreateWork = can('work.items.create')")
    expect(source).toContain("const canSubmitRequest = can('work.requests.create')")
    expect(source).toContain("searchParams.get('request') === 'new'")
    expect(source).toContain("next.set('request', 'new')")
    expect(source).toContain("onClick={() => navigate('/work/new')}")
    expect(source).toContain('className="work-mobile-create"')
  })
})
