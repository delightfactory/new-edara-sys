// src/components/notifications/NotificationCenter.tsx
// ─────────────────────────────────────────────────────────────
// Full notifications page — filters, search, pagination.
// Premium design with stats bar and chip filters.
// ─────────────────────────────────────────────────────────────

import { useSearchParams } from 'react-router-dom'
import { BellOff, CheckCheck, Bell, AlertTriangle, Eye } from 'lucide-react'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import { Skeleton } from '@/components/ui/Skeleton'
import {
  useNotificationsQuery,
  useMarkAsReadMutation,
  useMarkAllAsReadMutation,
  useArchiveMutation,
  useDeleteMutation,
} from '@/hooks/useNotificationQueries'
import { useNotificationStore } from '@/stores/notification-store'
import NotificationItem from './NotificationItem'
import type { NotificationCategory, NotificationPriority, NotificationFilters } from '@/lib/notifications/types'

// ── Category filter chips ─────────────────────────────────────
const CATEGORY_CHIPS: { value: string; label: string; color: string }[] = [
  { value: '',                  label: 'الكل',         color: '' },
  { value: 'hr_attendance',     label: 'الحضور',       color: '#6366f1' },
  { value: 'hr_leaves',         label: 'الإجازات',     color: '#8b5cf6' },
  { value: 'hr_payroll',        label: 'الرواتب',      color: '#10b981' },
  { value: 'finance_expenses',  label: 'المصروفات',    color: '#f59e0b' },
  { value: 'finance_approvals', label: 'الموافقات',    color: '#3b82f6' },
  { value: 'inventory',         label: 'المخزون',      color: '#06b6d4' },
  { value: 'sales',             label: 'المبيعات',     color: '#ec4899' },
  { value: 'procurement',       label: 'المشتريات',    color: '#0891b2' },
  { value: 'system',            label: 'النظام',       color: '#6b7280' },
  { value: 'alerts',            label: 'التنبيهات',    color: '#ef4444' },
]

const READ_OPTIONS = [
  { value: '',      label: 'الكل' },
  { value: 'false', label: 'غير مقروء' },
  { value: 'true',  label: 'مقروء' },
]

const PRIORITY_OPTIONS: { value: string; label: string }[] = [
  { value: '',         label: 'كل الأولويات' },
  { value: 'critical', label: '🔴 حرج' },
  { value: 'high',     label: '🟠 عالي' },
  { value: 'medium',   label: '🔵 متوسط' },
  { value: 'low',      label: '⚪ منخفض' },
]

// ── Pagination ────────────────────────────────────────────────
function Pagination({
  page, totalPages, onPage,
}: {
  page: number; totalPages: number; onPage: (p: number) => void
}) {
  if (totalPages <= 1) return null
  return (
    <div className="nc-pagination">
      <button
        className="nc-page-btn"
        disabled={page <= 1}
        onClick={() => onPage(page - 1)}
        type="button"
      >
        السابق
      </button>
      <span className="nc-page-info">{page} / {totalPages}</span>
      <button
        className="nc-page-btn"
        disabled={page >= totalPages}
        onClick={() => onPage(page + 1)}
        type="button"
      >
        التالي
      </button>
    </div>
  )
}

// ── Main component ────────────────────────────────────────────

export default function NotificationCenter() {
  const [params, setParams] = useSearchParams()
  const unreadCount = useNotificationStore(s => s.unreadCount)

  const page       = parseInt(params.get('page') ?? '1', 10)
  const category   = (params.get('category') ?? '') as NotificationCategory | ''
  const isReadRaw  = params.get('isRead') ?? ''
  const search     = params.get('search') ?? ''
  const priority   = (params.get('priority') ?? '') as NotificationPriority | ''
  const archived   = params.get('archived') === 'true'

  const filters: NotificationFilters = {
    ...(category ? { category } : {}),
    ...(isReadRaw !== '' ? { isRead: isReadRaw === 'true' } : {}),
    ...(search ? { search } : {}),
    ...(priority ? { priority } : {}),
    isArchived: archived,
  }

  const setParam = (key: string, val: string) => {
    const next = new URLSearchParams(params)
    if (val) next.set(key, val); else next.delete(key)
    next.delete('page')
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
  const del      = useDeleteMutation()

  const totalCount = data?.count ?? 0

  return (
    <div className="nc-page">
      <div className="nc-container">
        <PageHeader
          title={archived ? 'الأرشيف' : 'مركز الإشعارات'}
          subtitle={data ? `${totalCount} إشعار` : undefined}
          actions={
            !archived && unreadCount > 0 ? (
              <button
                className="nc-mark-all-btn"
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

        {/* Stats bar */}
        {!archived && (
          <div className="nc-stats">
            <div className="nc-stat">
              <div className="nc-stat-icon nc-stat-icon--total">
                <Bell size={16} />
              </div>
              <div className="nc-stat-info">
                <span className="nc-stat-value">{totalCount}</span>
                <span className="nc-stat-label">إجمالي</span>
              </div>
            </div>
            <div className="nc-stat">
              <div className="nc-stat-icon nc-stat-icon--unread">
                <Eye size={16} />
              </div>
              <div className="nc-stat-info">
                <span className="nc-stat-value">{unreadCount}</span>
                <span className="nc-stat-label">غير مقروء</span>
              </div>
            </div>
          </div>
        )}

        {/* Category chips */}
        <div className="nc-chips" role="tablist">
          {CATEGORY_CHIPS.map(chip => {
            const isActive = category === chip.value
            return (
              <button
                key={chip.value}
                role="tab"
                aria-selected={isActive}
                className={`nc-chip${isActive ? ' nc-chip--active' : ''}`}
                onClick={() => setParam('category', chip.value)}
                type="button"
                style={isActive && chip.color ? {
                  background: `${chip.color}14`,
                  color: chip.color,
                  borderColor: `${chip.color}40`,
                } : undefined}
              >
                {chip.label}
              </button>
            )
          })}
        </div>

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
            value={priority}
            onChange={e => setParam('priority', e.target.value)}
            aria-label="الأولوية"
          >
            {PRIORITY_OPTIONS.map(opt => (
              <option key={opt.value} value={opt.value}>{opt.label}</option>
            ))}
          </select>
          {!archived && (
            <select
              className="form-select nc-select"
              value={isReadRaw}
              onChange={e => setParam('isRead', e.target.value)}
              aria-label="حالة القراءة"
            >
              {READ_OPTIONS.map(opt => (
                <option key={opt.value} value={opt.value}>{opt.label}</option>
              ))}
            </select>
          )}
        </div>

        {/* List */}
        <div className="nc-list-card">
          {isLoading ? (
            <div role="list" aria-label="جاري التحميل">
              {[1, 2, 3, 4, 5].map(i => (
                <div key={i} className="nc-skeleton-row">
                  <Skeleton width={40} height={40} className="nc-skeleton-icon" />
                  <div className="nc-skeleton-content">
                    <Skeleton width="55%" height={14} />
                    <Skeleton width="90%" height={12} />
                    <Skeleton width="25%" height={10} />
                  </div>
                </div>
              ))}
            </div>
          ) : isError ? (
            <div className="nc-empty">
              <div className="nc-empty-icon nc-empty-icon--error">
                <AlertTriangle size={32} />
              </div>
              <p className="nc-empty-title">تعذّر تحميل الإشعارات</p>
              <p className="nc-empty-text">تحقق من اتصالك بالإنترنت وأعد المحاولة</p>
            </div>
          ) : !data || data.data.length === 0 ? (
            <div className="nc-empty">
              <div className="nc-empty-icon">
                <BellOff size={32} />
              </div>
              <p className="nc-empty-title">
                {archived ? 'لا توجد إشعارات مؤرشفة' : 'لا توجد إشعارات'}
              </p>
              <p className="nc-empty-text">
                {search || category || isReadRaw
                  ? 'حاول تعديل معايير البحث'
                  : (archived ? 'ستظهر هنا الإشعارات التي تؤرشفها' : 'ستظهر إشعاراتك الجديدة هنا')
                }
              </p>
            </div>
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

        {data && (
          <Pagination page={page} totalPages={data.totalPages} onPage={setPage} />
        )}
      </div>

      <style>{`
        .nc-page {
          padding: var(--space-6);
          min-height: 100%;
          animation: fade-in-up 0.3s ease-out;
        }
        .nc-container {
          max-width: 800px;
        }

        /* Stats */
        .nc-stats {
          display: flex;
          gap: var(--space-4);
          margin-bottom: var(--space-5);
        }
        .nc-stat {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface);
          border: 1px solid var(--border-primary);
          border-radius: 12px;
          flex: 1;
          transition: box-shadow 0.2s;
        }
        .nc-stat:hover { box-shadow: 0 2px 8px rgba(0,0,0,0.05); }
        .nc-stat-icon {
          width: 36px;
          height: 36px;
          border-radius: 10px;
          display: flex;
          align-items: center;
          justify-content: center;
        }
        .nc-stat-icon--total {
          background: rgba(37,99,235,0.1);
          color: #2563eb;
        }
        .nc-stat-icon--unread {
          background: rgba(245,158,11,0.1);
          color: #f59e0b;
        }
        .nc-stat-info {
          display: flex;
          flex-direction: column;
        }
        .nc-stat-value {
          font-size: var(--text-lg, 17px);
          font-weight: 700;
          color: var(--text-primary);
          line-height: 1.2;
        }
        .nc-stat-label {
          font-size: var(--text-xs, 12px);
          color: var(--text-muted);
        }

        /* Category chips */
        .nc-chips {
          display: flex;
          gap: var(--space-2);
          margin-bottom: var(--space-4);
          overflow-x: auto;
          scrollbar-width: none;
          padding-bottom: 2px;
        }
        .nc-chips::-webkit-scrollbar { display: none; }
        .nc-chip {
          padding: 6px 14px;
          border-radius: 20px;
          border: 1px solid var(--border-primary);
          background: var(--bg-surface);
          font-size: var(--text-xs, 12px);
          font-family: var(--font-sans);
          font-weight: 500;
          color: var(--text-secondary);
          cursor: pointer;
          white-space: nowrap;
          transition: all 0.2s;
          flex-shrink: 0;
        }
        .nc-chip:hover:not(.nc-chip--active) {
          background: var(--bg-hover);
          border-color: var(--text-muted);
        }
        .nc-chip--active {
          font-weight: 600;
        }

        /* Filters */
        .nc-filters {
          display: flex;
          gap: var(--space-3);
          margin-bottom: var(--space-4);
          flex-wrap: wrap;
          align-items: center;
        }
        .nc-search { flex: 1; min-width: 180px; }
        .nc-select { flex: 0 0 auto; min-width: 130px; }

        /* Mark all button */
        .nc-mark-all-btn {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          padding: var(--space-2) var(--space-3);
          border: 1px solid var(--border-primary);
          border-radius: 8px;
          background: var(--bg-surface);
          font-family: var(--font-sans);
          font-size: var(--text-xs, 12px);
          font-weight: 500;
          color: var(--text-secondary);
          cursor: pointer;
          transition: all 0.15s;
        }
        .nc-mark-all-btn:hover {
          background: var(--primary, #2563eb);
          color: #fff;
          border-color: var(--primary, #2563eb);
        }

        /* List card */
        .nc-list-card {
          border-radius: 16px;
          overflow: hidden;
          border: 1px solid var(--border-primary);
          background: var(--bg-surface);
          box-shadow: 0 1px 3px rgba(0,0,0,0.04);
        }

        /* Empty state */
        .nc-empty {
          display: flex;
          flex-direction: column;
          align-items: center;
          justify-content: center;
          padding: var(--space-12) var(--space-6);
          text-align: center;
        }
        .nc-empty-icon {
          width: 72px;
          height: 72px;
          border-radius: 20px;
          background: var(--bg-hover, rgba(0,0,0,0.04));
          color: var(--text-muted);
          display: flex;
          align-items: center;
          justify-content: center;
          margin-bottom: var(--space-4);
        }
        .nc-empty-icon--error {
          background: rgba(220,38,38,0.08);
          color: #dc2626;
        }
        .nc-empty-title {
          font-size: var(--text-sm, 14px);
          font-weight: 600;
          color: var(--text-primary);
          margin-bottom: var(--space-1);
        }
        .nc-empty-text {
          font-size: var(--text-xs, 12px);
          color: var(--text-muted);
        }

        /* Skeleton */
        .nc-skeleton-row {
          padding: var(--space-4);
          display: flex;
          gap: 14px;
          border-bottom: 1px solid var(--border-primary);
        }
        .nc-skeleton-icon { border-radius: 12px !important; }
        .nc-skeleton-content {
          flex: 1;
          display: flex;
          flex-direction: column;
          gap: 8px;
        }

        /* Pagination */
        .nc-pagination {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-4);
          margin-top: var(--space-6);
        }
        .nc-page-btn {
          padding: var(--space-2) var(--space-4);
          border: 1px solid var(--border-primary);
          border-radius: 8px;
          background: var(--bg-surface);
          font-family: var(--font-sans);
          font-size: var(--text-sm, 14px);
          color: var(--text-secondary);
          cursor: pointer;
          transition: all 0.15s;
        }
        .nc-page-btn:hover:not(:disabled) {
          background: var(--primary, #2563eb);
          color: #fff;
          border-color: var(--primary, #2563eb);
        }
        .nc-page-btn:disabled {
          opacity: 0.4;
          cursor: not-allowed;
        }
        .nc-page-info {
          font-size: var(--text-sm, 14px);
          color: var(--text-muted);
          font-weight: 500;
        }

        @media (max-width: 768px) {
          .nc-page { padding: var(--space-4); }
          .nc-filters {
            flex-direction: column;
            align-items: stretch;
          }
          .nc-select { min-width: unset; }
          .nc-stats { flex-direction: column; }
        }
      `}</style>
    </div>
  )
}
