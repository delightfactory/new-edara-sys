// src/components/notifications/NotificationCenter.tsx
// ─────────────────────────────────────────────────────────────
// Full notifications page — filters, search, pagination, archived tab.
// URL params: ?category=&isRead=&priority=&archived=true&page=&search=
// ─────────────────────────────────────────────────────────────

import { useSearchParams } from 'react-router-dom'
import { BellOff, CheckCheck, Trash2 } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import EmptyState from '@/components/shared/EmptyState'
import SearchInput from '@/components/shared/SearchInput'
import { Skeleton } from '@/components/ui/Skeleton'
import {
  useNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useArchiveMutation,
  useDeleteMutation,
} from '@/hooks/useNotificationQueries'
import NotificationItem from './NotificationItem'
import type { NotificationCategory, NotificationPriority, NotificationFilters } from '@/lib/notifications/types'

// ── Category options — all values match notification_category DB enum ─
const CATEGORY_OPTIONS: { value: string; label: string }[] = [
  { value: '',                  label: 'كل الفئات' },
  { value: 'hr_attendance',     label: 'الحضور' },
  { value: 'hr_leaves',         label: 'الإجازات' },
  { value: 'hr_payroll',        label: 'الرواتب' },
  { value: 'finance_expenses',  label: 'المصروفات' },
  { value: 'finance_approvals', label: 'الموافقات' },
  { value: 'inventory',         label: 'المخزون' },
  { value: 'sales',             label: 'المبيعات' },
  { value: 'procurement',       label: 'المشتريات' },
  { value: 'tasks',             label: 'المهام' },
  { value: 'system',            label: 'النظام' },
  { value: 'alerts',            label: 'التنبيهات' },
]

const READ_OPTIONS = [
  { value: '',      label: 'الكل' },
  { value: 'false', label: 'غير مقروء' },
  { value: 'true',  label: 'مقروء' },
]

// C-02: Priority filter — matches notification_priority DB enum
const PRIORITY_OPTIONS: { value: string; label: string }[] = [
  { value: '',         label: 'كل الأولويات' },
  { value: 'critical', label: '🔴 حرج' },
  { value: 'high',     label: '🟠 عالي' },
  { value: 'medium',   label: '🟡 متوسط' },
  { value: 'low',      label: '⚪ منخفض' },
]

// ── Pagination component ──────────────────────────────────────
function Pagination({
  page,
  totalPages,
  onPage,
}: {
  page: number
  totalPages: number
  onPage: (p: number) => void
}) {
  if (totalPages <= 1) return null
  return (
    <div className="nc-pagination">
      <button
        className="btn btn-ghost btn-sm"
        disabled={page <= 1}
        onClick={() => onPage(page - 1)}
        type="button"
        aria-label="الصفحة السابقة"
      >
        السابق
      </button>
      <span className="nc-page-info">{page} / {totalPages}</span>
      <button
        className="btn btn-ghost btn-sm"
        disabled={page >= totalPages}
        onClick={() => onPage(page + 1)}
        type="button"
        aria-label="الصفحة التالية"
      >
        التالي
      </button>
    </div>
  )
}

// ── Main component ────────────────────────────────────────────

export default function NotificationCenter() {
  const [params, setParams] = useSearchParams()

  // Read ALL filters from URL — single source of truth
  const page       = parseInt(params.get('page') ?? '1', 10)
  const category   = (params.get('category') ?? '') as NotificationCategory | ''
  const isReadRaw  = params.get('isRead') ?? ''
  const search     = params.get('search') ?? ''
  const priority   = (params.get('priority') ?? '') as NotificationPriority | ''
  const archived   = params.get('archived') === 'true'  // C-03: archived tab toggle

  const filters: NotificationFilters = {
    ...(category ? { category } : {}),
    ...(isReadRaw !== '' ? { isRead: isReadRaw === 'true' } : {}),
    ...(search ? { search } : {}),
    ...(priority ? { priority } : {}),
    // archived tab always shows archived; normal tab explicitly excludes them
    isArchived: archived ? true : false,
  }

  const setParam = (key: string, val: string) => {
    const next = new URLSearchParams(params)
    if (val) next.set(key, val); else next.delete(key)
    next.delete('page') // reset to page 1 on filter change
    setParams(next)
  }



  const setPage = (p: number) => {
    const next = new URLSearchParams(params)
    next.set('page', String(p))
    setParams(next)
  }

  const { data, isLoading, isError } = useNotificationsQuery({ page, filters })
  const markRead = useMarkAsReadMutation()
  const markAll  = useMarkAllAsReadMutation()
  const archive  = useArchiveMutation()
  const del      = useDeleteMutation()  // C-03: hard-delete for archived items

  return (
    <div className="nc-page">
      <div className="nc-container">
      <PageHeader
          title="مركز الإشعارات"
          subtitle={data ? `${data.count} إشعار` : undefined}
          actions={
            !archived ? (
              <button
                className="btn btn-ghost btn-sm"
                onClick={() => markAll.mutate(undefined)}
                type="button"
                aria-label="تحديد الكل كمقروء"
              >
                <CheckCheck size={15} />
                <span>تحديد الكل كمقروء</span>
              </button>
            ) : null
          }
        />



        {/* Filters bar */}
        <div className="nc-filters">
          <SearchInput
            value={search}
            onChange={v => setParam('search', v)}
            placeholder="بحث في الإشعارات..."
            className="nc-search"
          />
          <select
            className="form-select nc-select"
            value={category}
            onChange={e => setParam('category', e.target.value)}
            aria-label="تصفية حسب الفئة"
          >
            {CATEGORY_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
          {/* C-02: Priority filter — BUG-11 */}
          <select
            className="form-select nc-select"
            value={priority}
            onChange={e => setParam('priority', e.target.value)}
            aria-label="تصفية حسب الأولوية"
          >
            {PRIORITY_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
          {/* isRead filter hidden in archived tab — all archived are read */}
          {!archived && (
            <select
              className="form-select nc-select"
              value={isReadRaw}
              onChange={e => setParam('isRead', e.target.value)}
              aria-label="تصفية حسب حالة القراءة"
            >
              {READ_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          )}
        </div>

        {/* List */}
        <div className="card nc-list-card">
          {isLoading ? (
            <div role="list" aria-label="جاري التحميل">
              {[1, 2, 3, 4, 5].map(i => (
                <div key={i} style={{ padding: 'var(--space-4)', display: 'flex', gap: 14, borderBottom: '1px solid var(--border-primary)' }}>
                  <Skeleton width={36} height={36} className="skeleton-circle" />
                  <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 8 }}>
                    <Skeleton width="55%" height={14} />
                    <Skeleton width="90%" height={12} />
                    <Skeleton width="25%" height={10} />
                  </div>
                </div>
              ))}
            </div>
          ) : isError ? (
            <EmptyState
              icon={<BellOff size={40} />}
              title="تعذّر تحميل الإشعارات"
              text="تحقق من اتصالك بالإنترنت وأعد المحاولة"
            />
          ) : !data || data.data.length === 0 ? (
            <EmptyState
              icon={<BellOff size={40} />}
              title={archived ? 'لا توجد إشعارات مؤرشفة' : 'لا توجد إشعارات'}
              text={search || category || isReadRaw ? 'حاول تعديل معايير البحث' : (archived ? 'ستظهر هنا الإشعارات التي تؤرشفها' : 'ستظهر إشعاراتك الجديدة هنا')}
            />
          ) : (
            <div role="list" aria-label="قائمة الإشعارات">
              {data.data.map(n => (
                <NotificationItem
                  key={n.id}
                  notification={n}
                  compact={false}
                  onRead={!archived ? id => markRead.mutate(id) : undefined}
                  onArchive={!archived ? id => archive.mutate(id) : undefined}
                  onDelete={archived ? id => del.mutate(id) : undefined}
                />
              ))}
            </div>
          )}
        </div>

        {/* Pagination */}
        {data && (
          <Pagination
            page={page}
            totalPages={data.totalPages}
            onPage={setPage}
          />
        )}
      </div>

      <style>{`
        .nc-page {
          padding: var(--space-6);
          min-height: 100%;
        }
        .nc-container {
          max-width: 800px;
        }

        .nc-filters {
          display: flex;
          gap: var(--space-3);
          margin-bottom: var(--space-4);
          flex-wrap: wrap;
          align-items: center;
        }
        .nc-search {
          flex: 1;
          min-width: 180px;
        }
        .nc-select {
          flex: 0 0 auto;
          min-width: 130px;
        }

        .nc-list-card {
          border-radius: var(--radius-lg);
          overflow: hidden;
          padding: 0;
        }

        .nc-pagination {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-4);
          margin-top: var(--space-6);
        }
        .nc-page-info {
          font-size: var(--text-sm);
          color: var(--text-secondary);
        }

        /* C-03: Archived / Active tab switcher */
        .nc-tabs {
          display: flex;
          gap: var(--space-1);
          margin-bottom: var(--space-4);
          border-bottom: 1px solid var(--border-primary);
          padding-bottom: 0;
        }
        .nc-tab {
          padding: var(--space-2) var(--space-4);
          border: none;
          background: none;
          font-size: var(--text-sm);
          font-family: var(--font-sans);
          font-weight: 500;
          color: var(--text-secondary);
          cursor: pointer;
          border-bottom: 2px solid transparent;
          margin-bottom: -1px;
          transition: color var(--transition-fast), border-color var(--transition-fast);
        }
        .nc-tab--active {
          color: var(--primary, #2563eb);
          border-bottom-color: var(--primary, #2563eb);
        }
        .nc-tab:hover:not(.nc-tab--active) {
          color: var(--text-primary);
        }

        @media (max-width: 768px) {
          .nc-page {
            padding: var(--space-4);
          }
          .nc-filters {
            flex-direction: column;
            align-items: stretch;
          }
          .nc-select {
            min-width: unset;
          }
        }
      `}</style>
    </div>
  )
}
