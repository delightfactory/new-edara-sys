/**
 * RepCreditCommitmentPage.tsx — v5
 * تقرير الالتزام الائتماني لمسؤولي المحافظ
 *
 * v5 — فلاتر احترافية + Drawer فلاتر كاملة + Output Platform:
 *   - فلاتر الصفحة الرئيسية (client-side على dataset الصغير)
 *   - DrawerFilterBar داخل RepDetailDrawer
 *   - customersOnlyWithBalance: true افتراضياً
 *   - DocumentActions في header الصفحة
 *   - DocumentActions في header الـ Drawer
 *   - تقارير منفصلة لكل مستوى
 */

import React, { useState, useCallback, useMemo } from 'react'
import { useQuery } from '@tanstack/react-query'
import {
  getRepCreditCommitmentReport,
  getRepCreditCommitmentDetail,
  type RepCreditCommitmentRow,
  type RepCreditDetailRow,
} from '@/lib/services/rep-credit'
import { DocumentActions } from '@/features/output/components/DocumentActions'
import { computeCreditState } from '@/components/shared/CustomerCreditChip'

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function fmt(n: number): string {
  return n.toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })
}

const PAY_LABELS: Record<string, string> = {
  cash:   'نقدي',
  credit: 'آجل',
  mixed:  'مختلط',
}

function payLabel(term: string | null): string {
  if (!term) return '—'
  return PAY_LABELS[term] ?? term
}

// ─────────────────────────────────────────────────────────────
// Filter Models
// ─────────────────────────────────────────────────────────────

interface PageFilters {
  repSearch:         string
  includeUnassigned: boolean
  overdueOnly:       boolean
  portfolioMin:      string
  portfolioMax:      string
  createdDebtMin:    string
  createdDebtMax:    string
  collectionsMin:    string
  collectionsMax:    string
  sortBy:            'none' | 'portfolio_desc' | 'created_debt_desc' | 'collections_desc' | 'overdue_desc' | 'rep_name_asc'
}

const DEFAULT_PAGE_FILTERS: PageFilters = {
  repSearch:         '',
  includeUnassigned: true,
  overdueOnly:       false,
  portfolioMin:      '',
  portfolioMax:      '',
  createdDebtMin:    '',
  createdDebtMax:    '',
  collectionsMin:    '',
  collectionsMax:    '',
  sortBy:            'none',
}

type CustomerState = 'all' | 'exceeded' | 'near-limit' | 'within-limit' | 'no-limit'
type DrawerSection = 'all' | 'customers' | 'orders' | 'receipts'

interface DrawerFilters {
  search:                 string
  customersOnlyWithBalance: boolean
  customerPaymentTerms:   'all' | 'credit' | 'mixed' | 'cash'
  customerState:          CustomerState
  sections:               DrawerSection
}

const DEFAULT_DRAWER_FILTERS: DrawerFilters = {
  search:                 '',
  customersOnlyWithBalance: true,
  customerPaymentTerms:   'all',
  customerState:          'all',
  sections:               'all',
}

// تحويل DrawerFilters لـ params في DocumentActions
function drawerFiltersToParams(f: DrawerFilters, repName: string, isUnassigned: boolean): Record<string, string> {
  const p: Record<string, string> = {}
  if (f.search)                        p['search']                 = f.search
  if (!f.customersOnlyWithBalance)     p['customersOnlyWithBalance'] = 'false'
  if (f.customerPaymentTerms !== 'all') p['customerPaymentTerms']  = f.customerPaymentTerms
  if (f.customerState        !== 'all') p['customerState']          = f.customerState
  if (f.sections             !== 'all') p['sections']               = f.sections
  p['repName']       = repName
  p['isUnassigned']  = isUnassigned ? 'true' : 'false'
  return p
}

// تحويل PageFilters لـ params في DocumentActions
function pageFiltersToParams(f: PageFilters): Record<string, string> {
  const p: Record<string, string> = {}
  if (f.repSearch)          p['repSearch']        = f.repSearch
  if (!f.includeUnassigned) p['includeUnassigned'] = 'false'
  if (f.overdueOnly)        p['overdueOnly']       = 'true'
  if (f.portfolioMin)       p['portfolioMin']      = f.portfolioMin
  if (f.portfolioMax)       p['portfolioMax']      = f.portfolioMax
  if (f.createdDebtMin)     p['createdDebtMin']    = f.createdDebtMin
  if (f.createdDebtMax)     p['createdDebtMax']    = f.createdDebtMax
  if (f.collectionsMin)     p['collectionsMin']    = f.collectionsMin
  if (f.collectionsMax)     p['collectionsMax']    = f.collectionsMax
  if (f.sortBy !== 'none')  p['sortBy']            = f.sortBy
  return p
}

// ─────────────────────────────────────────────────────────────
// Row Filtering
// ─────────────────────────────────────────────────────────────

function applyPageFilters(rows: RepCreditCommitmentRow[], f: PageFilters): RepCreditCommitmentRow[] {
  let result = [...rows]

  if (f.repSearch) {
    const q = f.repSearch.toLowerCase().trim()
    result = result.filter(r => r.rep_name.toLowerCase().includes(q))
  }
  if (!f.includeUnassigned) {
    result = result.filter(r => !r.is_unassigned)
  }
  if (f.overdueOnly) {
    result = result.filter(r => r.overdue_customers_count > 0)
  }
  if (f.portfolioMin) result = result.filter(r => r.portfolio_balance >= parseFloat(f.portfolioMin))
  if (f.portfolioMax) result = result.filter(r => r.portfolio_balance <= parseFloat(f.portfolioMax))
  if (f.createdDebtMin) result = result.filter(r => r.created_debt >= parseFloat(f.createdDebtMin))
  if (f.createdDebtMax) result = result.filter(r => r.created_debt <= parseFloat(f.createdDebtMax))
  if (f.collectionsMin) result = result.filter(r => r.confirmed_collections >= parseFloat(f.collectionsMin))
  if (f.collectionsMax) result = result.filter(r => r.confirmed_collections <= parseFloat(f.collectionsMax))

  if (f.sortBy !== 'none') {
    result.sort((a, b) => {
      switch (f.sortBy) {
        case 'portfolio_desc':    return b.portfolio_balance - a.portfolio_balance
        case 'created_debt_desc': return b.created_debt - a.created_debt
        case 'collections_desc':  return b.confirmed_collections - a.confirmed_collections
        case 'overdue_desc':      return b.overdue_customers_count - a.overdue_customers_count
        case 'rep_name_asc':      return a.rep_name.localeCompare(b.rep_name, 'ar')
        default: return 0
      }
    })
  }

  return result
}

function deriveFilteredSummary(rows: RepCreditCommitmentRow[]) {
  const realReps = rows.filter(r => !r.is_unassigned)
  return {
    totalReps:                 realReps.length,
    totalPortfolio:            rows.reduce((s, r) => s + r.portfolio_balance, 0),
    totalCreatedDebt:          realReps.reduce((s, r) => s + r.created_debt, 0),
    totalConfirmedCollections: realReps.reduce((s, r) => s + r.confirmed_collections, 0),
    hasUnassigned:             rows.some(r => r.is_unassigned),
    unassignedBalance:         rows.find(r => r.is_unassigned)?.portfolio_balance ?? 0,
  }
}

// ─────────────────────────────────────────────────────────────
// Drawer Customer/Order/Receipt filtering
// ─────────────────────────────────────────────────────────────

function filterCustomers(customers: RepCreditDetailRow[], f: DrawerFilters): RepCreditDetailRow[] {
  let result = [...customers]
  if (f.customersOnlyWithBalance) {
    result = result.filter(c => (c.amount_1 ?? 0) > 0)
  }
  if (f.search) {
    const q = f.search.toLowerCase().trim()
    result = result.filter(c =>
      c.entity_name.toLowerCase().includes(q) || (c.entity_ref ?? '').toLowerCase().includes(q)
    )
  }
  if (f.customerPaymentTerms !== 'all') {
    result = result.filter(c => c.status_text === f.customerPaymentTerms)
  }
  if (f.customerState !== 'all') {
    result = result.filter(c => {
      const st = computeCreditState({
        payment_terms:   c.status_text ?? 'cash',
        credit_limit:    c.amount_2 ?? 0,
        current_balance: c.amount_1 ?? 0,
      })
      switch (f.customerState) {
        case 'exceeded':
          return st.type === 'credit' && (c.amount_1 ?? 0) > (c.amount_2 ?? 0)
        case 'near-limit':
          return st.type === 'credit' && st.usedPct >= 0.8 && st.usedPct <= 1
        case 'within-limit':
          return st.type === 'credit' && st.usedPct < 0.8
        case 'no-limit':
          return st.type === 'no_limit'
        default: return true
      }
    })
  }
  return result
}

function filterOrders(orders: RepCreditDetailRow[], f: DrawerFilters): RepCreditDetailRow[] {
  if (!f.search) return orders
  const q = f.search.toLowerCase().trim()
  return orders.filter(o =>
    (o.entity_ref ?? '').toLowerCase().includes(q) || o.entity_name.toLowerCase().includes(q)
  )
}

function filterReceipts(receipts: RepCreditDetailRow[], f: DrawerFilters): RepCreditDetailRow[] {
  if (!f.search) return receipts
  const q = f.search.toLowerCase().trim()
  return receipts.filter(r =>
    (r.entity_ref ?? '').toLowerCase().includes(q) || r.entity_name.toLowerCase().includes(q)
  )
}

// ─────────────────────────────────────────────────────────────
// Static styles
// ─────────────────────────────────────────────────────────────

const css = {
  page: {
    padding: 'var(--space-6)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-6)',
    direction: 'rtl' as const,
    fontFamily: 'var(--font-sans)',
    minHeight: '100%',
    background: 'var(--bg-app)',
  },
  pageTitle: {
    fontSize: 'var(--text-2xl)',
    fontWeight: 700,
    color: 'var(--text-primary)',
    margin: 0,
  },
  pageSubtitle: {
    fontSize: 'var(--text-sm)',
    color: 'var(--text-muted)',
    marginTop: 'var(--space-1)',
    margin: 'var(--space-1) 0 0',
  },
  kpiGrid: {
    display: 'grid',
    gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
    gap: 'var(--space-4)',
  },
  kpiCard: (accent: string) => ({
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-primary)',
    borderTop: `3px solid ${accent}`,
    borderRadius: 'var(--radius-lg)',
    padding: 'var(--space-5)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-2)',
    boxShadow: 'var(--shadow-sm)',
  }),
  kpiLabel: {
    fontSize: 'var(--text-xs)',
    color: 'var(--text-secondary)',
    fontWeight: 500,
  },
  kpiValue: (accent: string) => ({
    fontSize: 'var(--text-xl)',
    fontWeight: 700,
    color: accent,
  }),
  kpiSub: {
    fontSize: 'var(--text-xs)',
    color: 'var(--text-muted)',
  },
  warningBanner: {
    background: 'var(--color-warning-light)',
    border: '1px solid var(--color-warning)',
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4) var(--space-5)',
    display: 'flex',
    gap: 'var(--space-3)',
    alignItems: 'flex-start',
  },
  warningText: {
    fontSize: 'var(--text-sm)',
    color: 'var(--color-warning)',
    lineHeight: 1.6,
  },
  errorBanner: {
    background: 'var(--color-danger-light)',
    border: '1px solid var(--color-danger)',
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4)',
    fontSize: 'var(--text-sm)',
    color: 'var(--color-danger)',
  },
  // Filters bar
  filterBar: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-primary)',
    borderRadius: 'var(--radius-lg)',
    padding: 'var(--space-4)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-3)',
  },
  filterRow: {
    display: 'flex',
    gap: 'var(--space-3)',
    flexWrap: 'wrap' as const,
    alignItems: 'center',
  },
  tableWrapper: {
    background: 'var(--bg-surface)',
    border: '1px solid var(--border-primary)',
    borderRadius: 'var(--radius-lg)',
    overflow: 'hidden',
    boxShadow: 'var(--shadow-sm)',
  },
  table: {
    width: '100%',
    borderCollapse: 'collapse' as const,
    fontSize: 'var(--text-sm)',
  },
  th: {
    padding: 'var(--space-3) var(--space-4)',
    textAlign: 'right' as const,
    fontWeight: 600,
    color: 'var(--text-secondary)',
    fontSize: 'var(--text-xs)',
    background: 'var(--bg-surface-2)',
    borderBottom: '2px solid var(--border-primary)',
    whiteSpace: 'nowrap' as const,
  },
  td: {
    padding: 'var(--space-3) var(--space-4)',
    borderBottom: '1px solid var(--divider)',
    color: 'var(--text-primary)',
    verticalAlign: 'middle' as const,
  },
  mobileCard: (isUnassigned: boolean) => ({
    background: 'var(--bg-surface)',
    border: `1px solid var(--border-primary)`,
    borderRight: isUnassigned ? '4px solid var(--color-warning)' : '4px solid var(--color-primary)',
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4)',
    cursor: 'pointer' as const,
    transition: 'box-shadow var(--transition-fast)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-3)',
  }),
  mobileCardGrid: {
    display: 'grid',
    gridTemplateColumns: '1fr 1fr',
    gap: 'var(--space-2)',
  },
  mobileCardField: {
    display: 'flex',
    flexDirection: 'column' as const,
    gap: '2px',
  },
  mobileCardLabel: {
    fontSize: '0.65rem',
    color: 'var(--text-muted)',
    fontWeight: 600,
    textTransform: 'uppercase' as const,
    letterSpacing: '0.03em',
  },
  mobileCardValue: {
    fontSize: 'var(--text-sm)',
    fontWeight: 700,
    color: 'var(--text-primary)',
  },
  badge: (bg: string, color: string) => ({
    display: 'inline-flex',
    alignItems: 'center',
    gap: '0.2rem',
    padding: '0.2rem 0.5rem',
    borderRadius: 'var(--radius-full)',
    fontSize: '0.7rem',
    fontWeight: 700,
    background: bg,
    color: color,
    whiteSpace: 'nowrap' as const,
  }),
  unassignedBadge: {
    display: 'inline-flex',
    alignItems: 'center',
    gap: '0.25rem',
    padding: '0.2rem 0.55rem',
    borderRadius: 'var(--radius-full)',
    fontSize: '0.7rem',
    fontWeight: 700,
    background: 'var(--color-warning-light)',
    color: 'var(--color-warning)',
  },
  overlay: {
    position: 'fixed' as const,
    inset: 0,
    background: 'var(--overlay-bg)',
    zIndex: 'var(--z-overlay)',
  },
  drawer: (isMobile: boolean) => isMobile
    ? {
        position: 'fixed' as const,
        bottom: 0,
        right: 0,
        left: 0,
        maxHeight: '90vh',
        background: 'var(--modal-bg)',
        borderRadius: 'var(--sheet-radius)',
        zIndex: 'var(--z-modal)',
        display: 'flex',
        flexDirection: 'column' as const,
        overflowY: 'auto' as const,
        boxShadow: 'var(--shadow-xl)',
      }
    : {
        position: 'fixed' as const,
        top: 0,
        right: 0,
        height: '100%',
        width: 'min(820px, 94vw)',
        background: 'var(--modal-bg)',
        boxShadow: 'var(--shadow-xl)',
        zIndex: 'var(--z-modal)',
        display: 'flex',
        flexDirection: 'column' as const,
        overflowY: 'auto' as const,
      },
  drawerHeader: {
    padding: 'var(--space-5) var(--space-6)',
    borderBottom: '1px solid var(--border-primary)',
    display: 'flex',
    justifyContent: 'space-between',
    alignItems: 'flex-start',
    position: 'sticky' as const,
    top: 0,
    background: 'var(--modal-bg)',
    zIndex: 1,
    gap: 'var(--space-3)',
    flexWrap: 'wrap' as const,
  },
  drawerBody: {
    padding: 'var(--space-5) var(--space-6)',
    display: 'flex',
    flexDirection: 'column' as const,
    gap: 'var(--space-6)',
  },
  closeBtn: {
    border: 'none',
    background: 'transparent',
    cursor: 'pointer',
    fontSize: '1.35rem',
    lineHeight: 1,
    color: 'var(--text-secondary)',
    padding: 'var(--space-1)',
    borderRadius: 'var(--radius-sm)',
    transition: 'color var(--transition-fast)',
    flexShrink: 0,
  },
  sectionTitle: {
    fontSize: 'var(--text-sm)',
    fontWeight: 700,
    color: 'var(--text-primary)',
    marginBottom: 'var(--space-3)',
    display: 'flex',
    alignItems: 'center',
    gap: 'var(--space-2)',
  },
  innerTableWrapper: {
    border: '1px solid var(--border-primary)',
    borderRadius: 'var(--radius-md)',
    overflow: 'hidden',
  },
  innerTable: {
    width: '100%',
    borderCollapse: 'collapse' as const,
    fontSize: 'var(--text-xs)',
  },
  innerTh: {
    padding: 'var(--space-2) var(--space-3)',
    background: 'var(--bg-surface-2)',
    borderBottom: '1px solid var(--border-primary)',
    fontWeight: 600,
    color: 'var(--text-secondary)',
    textAlign: 'right' as const,
    whiteSpace: 'nowrap' as const,
  },
  innerTd: {
    padding: 'var(--space-2) var(--space-3)',
    borderBottom: '1px solid var(--divider)',
    color: 'var(--text-primary)',
    verticalAlign: 'middle' as const,
  },
  notice: (type: 'warning' | 'info') => ({
    background: type === 'warning' ? 'var(--color-warning-light)' : 'var(--color-info-light)',
    border: `1px solid ${type === 'warning' ? 'var(--color-warning)' : 'var(--color-info)'}`,
    borderRadius: 'var(--radius-md)',
    padding: 'var(--space-4)',
    fontSize: 'var(--text-sm)',
    color: type === 'warning' ? 'var(--color-warning)' : 'var(--color-info)',
    lineHeight: 1.7,
  }),
  emptyRow: {
    padding: 'var(--space-6)',
    textAlign: 'center' as const,
    color: 'var(--text-muted)',
    fontSize: 'var(--text-sm)',
    background: 'var(--bg-surface-2)',
    borderRadius: 'var(--radius-md)',
  },
  skeleton: {
    background: 'var(--bg-surface-2)',
    borderRadius: 'var(--radius-md)',
    height: '2.5rem',
    animation: 'shimmer 1.5s infinite',
    backgroundSize: '200% 100%',
  },
}

// ─────────────────────────────────────────────────────────────
// useIsMobile
// ─────────────────────────────────────────────────────────────

function useIsMobile(): boolean {
  const [mobile, setMobile] = React.useState(() =>
    typeof window !== 'undefined' ? window.innerWidth <= 768 : false
  )
  React.useEffect(() => {
    const handler = () => setMobile(window.innerWidth <= 768)
    window.addEventListener('resize', handler)
    return () => window.removeEventListener('resize', handler)
  }, [])
  return mobile
}

// ─────────────────────────────────────────────────────────────
// Skeleton
// ─────────────────────────────────────────────────────────────

function Skeleton({ rows = 5 }: { rows?: number }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)', padding: 'var(--space-4)' }}>
      {Array.from({ length: rows }).map((_, i) => (
        <div key={i} style={css.skeleton} />
      ))}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Inner tables — Customer / Order / Receipt
// ─────────────────────────────────────────────────────────────

function CustomerTable({ customers, label }: { customers: RepCreditDetailRow[]; label: string }) {
  if (customers.length === 0) return <div style={css.emptyRow}>لا يوجد عملاء مطابقون للفلتر</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={css.innerTable}>
        <thead>
          <tr>
            <th style={css.innerTh}>الاسم</th>
            <th style={css.innerTh}>الكود</th>
            <th style={css.innerTh}>الرصيد الحالي</th>
            <th style={css.innerTh}>حد الائتمان</th>
            <th style={css.innerTh}>نوع الدفع</th>
            <th style={css.innerTh}>أيام الائتمان</th>
          </tr>
        </thead>
        <tbody>
          {customers.map(c => (
            <tr key={c.entity_id}>
              <td style={{ ...css.innerTd, fontWeight: 600 }}>{c.entity_name}</td>
              <td style={{ ...css.innerTd, fontFamily: 'monospace', color: 'var(--text-secondary)' }}>
                {c.entity_ref ?? '—'}
              </td>
              <td style={{
                ...css.innerTd,
                fontWeight: 700,
                color: c.amount_1 > 0 ? 'var(--color-danger)' : 'var(--color-success)',
              }}>
                {fmt(c.amount_1)}
              </td>
              <td style={css.innerTd}>{c.amount_2 != null ? fmt(c.amount_2) : '—'}</td>
              <td style={css.innerTd}>{payLabel(c.status_text)}</td>
              <td style={css.innerTd}>
                {c.amount_3 != null ? `${Math.round(c.amount_3)} يوم` : '—'}
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

function OrderTable({ orders }: { orders: RepCreditDetailRow[] }) {
  if (orders.length === 0) return <div style={css.emptyRow}>لا توجد فواتير مطابقة للفلتر</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={css.innerTable}>
        <thead>
          <tr>
            <th style={css.innerTh}>رقم الطلب</th>
            <th style={css.innerTh}>العميل</th>
            <th style={css.innerTh}>الصافي المتبقي</th>
            <th style={css.innerTh}>الإجمالي</th>
            <th style={css.innerTh}>المحصَّل</th>
            <th style={css.innerTh}>تاريخ التسليم</th>
            <th style={css.innerTh}>الأيام</th>
          </tr>
        </thead>
        <tbody>
          {orders.map(o => {
            const days = o.extra_int ?? 0
            return (
              <tr key={o.entity_id} style={{ background: days > 0 ? 'var(--color-danger-light)' : 'transparent' }}>
                <td style={{ ...css.innerTd, fontFamily: 'monospace', color: 'var(--color-info)' }}>
                  {o.entity_ref ?? '—'}
                </td>
                <td style={css.innerTd}>{o.entity_name}</td>
                <td style={{ ...css.innerTd, fontWeight: 700, color: 'var(--color-danger)' }}>
                  {fmt(o.amount_1)}
                </td>
                <td style={css.innerTd}>{o.amount_2 != null ? fmt(o.amount_2) : '—'}</td>
                <td style={css.innerTd}>{o.amount_3 != null ? fmt(o.amount_3) : '—'}</td>
                <td style={css.innerTd}>{o.date_1 ?? '—'}</td>
                <td style={{
                  ...css.innerTd,
                  color: days > 0 ? 'var(--color-danger)' : 'var(--color-success)',
                  fontWeight: 700,
                }}>
                  {o.extra_int != null ? o.extra_int : '—'}
                </td>
              </tr>
            )
          })}
        </tbody>
      </table>
    </div>
  )
}

function ReceiptTable({ receipts }: { receipts: RepCreditDetailRow[] }) {
  if (receipts.length === 0) return <div style={css.emptyRow}>لا توجد تحصيلات مطابقة للفلتر</div>
  return (
    <div style={{ overflowX: 'auto' }}>
      <table style={css.innerTable}>
        <thead>
          <tr>
            <th style={css.innerTh}>رقم الإيصالة</th>
            <th style={css.innerTh}>العميل</th>
            <th style={css.innerTh}>المبلغ</th>
            <th style={css.innerTh}>تاريخ المراجعة</th>
          </tr>
        </thead>
        <tbody>
          {receipts.map(r => (
            <tr key={r.entity_id}>
              <td style={{ ...css.innerTd, fontFamily: 'monospace', color: 'var(--color-success)' }}>
                {r.entity_ref ?? '—'}
              </td>
              <td style={css.innerTd}>{r.entity_name}</td>
              <td style={{ ...css.innerTd, fontWeight: 700, color: 'var(--color-success)' }}>
                {fmt(r.amount_1)}
              </td>
              <td style={css.innerTd}>{r.date_1 ?? '—'}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// DrawerFilterBar — شريط الفلاتر داخل الـ Drawer
// ─────────────────────────────────────────────────────────────

function DrawerFilterBar({
  filters,
  onChange,
  isUnassigned,
}: {
  filters:      DrawerFilters
  onChange:     (f: DrawerFilters) => void
  isUnassigned: boolean
}) {
  const [showAdvanced, setShowAdvanced] = React.useState(false)

  const hasActive =
    filters.search !== ''                  ||
    !filters.customersOnlyWithBalance      ||
    filters.customerPaymentTerms !== 'all' ||
    filters.customerState !== 'all'        ||
    filters.sections !== 'all'

  const update = (patch: Partial<DrawerFilters>) => onChange({ ...filters, ...patch })

  return (
    <div style={{
      background: 'var(--bg-surface-2)',
      border: '1px solid var(--border-primary)',
      borderRadius: 'var(--radius-md)',
      padding: 'var(--space-3)',
      display: 'flex',
      flexDirection: 'column',
      gap: 'var(--space-2)',
    }}>
      {/* الصف الأول */}
      <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap', alignItems: 'center' }}>
        {/* بحث */}
        <div style={{ position: 'relative', flex: '1 1 180px' }}>
          <span style={{
            position: 'absolute', insetInlineStart: 8,
            top: '50%', transform: 'translateY(-50%)',
            color: 'var(--text-muted)', fontSize: '0.8rem', pointerEvents: 'none',
          }}>🔍</span>
          <input
            type="text"
            placeholder="بحث باسم / كود..."
            value={filters.search}
            onChange={e => update({ search: e.target.value })}
            className="form-input"
            style={{ paddingInlineStart: 28, width: '100%', fontSize: 'var(--text-xs)' }}
          />
        </div>

        {/* الأقسام */}
        <select
          value={filters.sections}
          onChange={e => update({ sections: e.target.value as DrawerSection })}
          className="form-input"
          style={{ fontSize: 'var(--text-xs)', minWidth: 110 }}
        >
          <option value="all">كل الأقسام</option>
          <option value="customers">العملاء فقط</option>
          {!isUnassigned && <option value="orders">الفواتير فقط</option>}
          {!isUnassigned && <option value="receipts">التحصيلات فقط</option>}
        </select>

        {/* زر الفلاتر المتقدمة */}
        <button
          onClick={() => setShowAdvanced(v => !v)}
          className={`cm-pager-btn`}
          style={{
            flexShrink: 0,
            display: 'flex',
            alignItems: 'center',
            gap: 4,
            fontSize: 'var(--text-xs)',
            background: showAdvanced ? 'var(--color-primary-light)' : 'var(--bg-surface)',
            borderColor: showAdvanced ? 'var(--color-primary)' : 'var(--border-primary)',
            color: showAdvanced ? 'var(--color-primary)' : 'var(--text-secondary)',
          }}
        >
          ⚙ العملاء
          {hasActive && (
            <span style={{
              background: 'var(--color-primary)',
              color: '#fff',
              borderRadius: 99,
              padding: '1px 5px',
              fontSize: '0.6rem',
              fontWeight: 800,
            }}>!</span>
          )}
        </button>

        {/* إعادة تعيين */}
        {hasActive && (
          <button
            onClick={() => onChange(DEFAULT_DRAWER_FILTERS)}
            className="cm-pager-btn"
            style={{ fontSize: 'var(--text-xs)', color: 'var(--color-danger)', borderColor: 'var(--color-danger)', flexShrink: 0 }}
          >
            ✕
          </button>
        )}
      </div>

      {/* ── فلاتر العملاء المتقدمة ── */}
      {showAdvanced && (
        <div style={{
          borderTop: '1px solid var(--border-primary)',
          paddingTop: 'var(--space-2)',
          display: 'grid',
          gridTemplateColumns: 'repeat(auto-fit, minmax(160px, 1fr))',
          gap: 'var(--space-2)',
        }}>
          {/* لديهم رصيد فقط */}
          <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 'var(--text-xs)', cursor: 'pointer' }}>
            <input
              type="checkbox"
              checked={filters.customersOnlyWithBalance}
              onChange={e => update({ customersOnlyWithBalance: e.target.checked })}
            />
            <span>لديهم رصيد {'>'} 0 فقط</span>
          </label>

          {/* نوع الدفع */}
          <select
            value={filters.customerPaymentTerms}
            onChange={e => update({ customerPaymentTerms: e.target.value as any })}
            className="form-input"
            style={{ fontSize: 'var(--text-xs)' }}
          >
            <option value="all">كل طرق الدفع</option>
            <option value="credit">آجل فقط</option>
            <option value="mixed">مختلط فقط</option>
            <option value="cash">نقدي فقط</option>
          </select>

          {/* حالة الائتمان */}
          <select
            value={filters.customerState}
            onChange={e => update({ customerState: e.target.value as CustomerState })}
            className="form-input"
            style={{ fontSize: 'var(--text-xs)' }}
          >
            <option value="all">كل الحالات</option>
            <option value="exceeded">تجاوزوا الحد</option>
            <option value="near-limit">قريبون من الحد</option>
            <option value="within-limit">ضمن الحد</option>
            <option value="no-limit">بلا حد ائتماني</option>
          </select>
        </div>
      )}
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// RepDetailDrawer — مُحسَّن كاملاً
// ─────────────────────────────────────────────────────────────

interface DrawerProps {
  repId:        string | null
  repName:      string
  isUnassigned: boolean
  onClose:      () => void
}

function RepDetailDrawer({ repId, repName, isUnassigned, onClose }: DrawerProps) {
  const isMobile = useIsMobile()
  const [drawerFilters, setDrawerFilters] = React.useState<DrawerFilters>(DEFAULT_DRAWER_FILTERS)
  const [paper, setPaper] = React.useState<'a4-landscape' | 'a4-portrait'>('a4-landscape')

  const { data, isLoading, error } = useQuery({
    queryKey:  ['rep-credit-detail', repId],
    queryFn:   () => getRepCreditCommitmentDetail(repId),
    staleTime: 60_000,
  })

  // Close on Escape
  React.useEffect(() => {
    const handler = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', handler)
    return () => document.removeEventListener('keydown', handler)
  }, [onClose])

  // تطبيق الفلاتر بعد التحميل
  const showCustomers = drawerFilters.sections === 'all' || drawerFilters.sections === 'customers'
  const showOrders    = !isUnassigned && (drawerFilters.sections === 'all' || drawerFilters.sections === 'orders')
  const showReceipts  = !isUnassigned && (drawerFilters.sections === 'all' || drawerFilters.sections === 'receipts')

  const filteredCustomers = useMemo(() =>
    data && showCustomers ? filterCustomers(data.customers, drawerFilters) : [],
    [data, drawerFilters, showCustomers]
  )
  const filteredOrders = useMemo(() =>
    data && showOrders ? filterOrders(data.orders, drawerFilters) : [],
    [data, drawerFilters, showOrders]
  )
  const filteredReceipts = useMemo(() =>
    data && showReceipts ? filterReceipts(data.receipts, drawerFilters) : [],
    [data, drawerFilters, showReceipts]
  )

  const entityId = isUnassigned ? '__unassigned__' : (repId ?? '__unassigned__')
  const printParams = drawerFiltersToParams(drawerFilters, repName, isUnassigned)

  return (
    <>
      <div
        style={{ ...css.overlay, zIndex: 190 }}
        onClick={onClose}
        aria-hidden="true"
      />

      <div
        style={{ ...css.drawer(isMobile), zIndex: 200 }}
        role="dialog"
        aria-modal="true"
        aria-label={isUnassigned ? 'تفاصيل: العملاء غير المسندين' : `تفاصيل: ${repName}`}
      >
        {/* ── Header ── */}
        <div style={css.drawerHeader}>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)', flexWrap: 'wrap' as const }}>
              {isUnassigned && (
                <span style={css.unassignedBadge}>⚠ غير مسند</span>
              )}
              <h2 style={{ margin: 0, fontSize: 'var(--text-lg)', fontWeight: 700, color: 'var(--text-primary)' }}>
                {isUnassigned ? 'العملاء غير المسندين' : repName}
              </h2>
            </div>
            <p style={{ margin: 'var(--space-1) 0 0', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              {isUnassigned
                ? 'عملاء نشطون عليهم رصيد ولم يُحدَّد لهم مسؤول متابعة'
                : `مسؤول المحفظة — ${repName}`}
            </p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
            {/* Paper Selector */}
            <select
              value={paper}
              onChange={e => setPaper(e.target.value as 'a4-landscape' | 'a4-portrait')}
              title="اختر المقاس"
              style={{
                padding: '4px 8px', fontSize: '12px',
                border: '1px solid var(--border-primary)', borderRadius: '4px'
              }}
            >
              <option value="a4-landscape">A4 بالعرض</option>
              <option value="a4-portrait">A4 بالطول</option>
            </select>
            {/* زر الطباعة في Header الـ Drawer */}
            <DocumentActions
              kind="rep-credit-commitment-detail-report"
              entityId={entityId}
              params={printParams}
              paperProfileId={paper}
              compact={true}
            />
            <button onClick={onClose} style={css.closeBtn} aria-label="إغلاق">✕</button>
          </div>
        </div>

        {/* ── Body ── */}
        <div style={css.drawerBody}>

          {/* تنبيه الصف الصناعي */}
          {isUnassigned && (
            <div style={css.notice('warning')}>
              <strong>⚠ تنبيه:</strong> هؤلاء العملاء عليهم أرصدة مستحقة ولم يتم تعيين مسؤول
              متابعة لهم حتى الآن. يُرجى الانتقال إلى صفحة إدارة العملاء وإسناد كل عميل
              إلى المسؤول المناسب.
              <br />
              <strong>ملاحظة:</strong> لا تُنسب المديونية المنشأة أو التحصيلات إلى هذا الصف —
              هذه البيانات منسوبة إلى أفراد بعينهم عبر سجلات الفواتير والإيصالات.
            </div>
          )}

          {/* ── Filter Bar ── */}
          <DrawerFilterBar
            filters={drawerFilters}
            onChange={setDrawerFilters}
            isUnassigned={isUnassigned}
          />

          {isLoading && <Skeleton rows={8} />}

          {error && (
            <div style={css.notice('warning')}>
              حدث خطأ عند تحميل البيانات. يرجى المحاولة لاحقاً.
            </div>
          )}

          {data && (
            <>
              {/* القسم 1: العملاء */}
              {showCustomers && (
                <div>
                  <div style={css.sectionTitle}>
                    <span>👥</span>
                    <span>
                      {isUnassigned
                        ? `العملاء غير المسندين — رصيد قائم (${filteredCustomers.length})`
                        : `العملاء المسندون${drawerFilters.customersOnlyWithBalance ? ' (برصيد)' : ''} (${filteredCustomers.length})`}
                    </span>
                  </div>
                  {/* التوضيح أسفل العنوان عند عرض الكل */}
                  {!drawerFilters.customersOnlyWithBalance && !isUnassigned && (
                    <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', margin: '0 0 var(--space-2)' }}>
                      ℹ️ يشمل عملاء رصيدهم صفر — الافتراضي: برصيد {'>'} 0 فقط
                    </p>
                  )}
                  <div style={css.innerTableWrapper}>
                    <CustomerTable customers={filteredCustomers} label="العملاء" />
                  </div>
                </div>
              )}

              {/* القسم 2 & 3: للمسؤولين الحقيقيين فقط */}
              {!isUnassigned && (
                <>
                  {showOrders && (
                    <div>
                      <div style={css.sectionTitle}>
                        <span>📄</span>
                        <span>الفواتير المنشأة بواسطته — صافي متبقٍ ({filteredOrders.length})</span>
                      </div>
                      <div style={css.innerTableWrapper}>
                        <OrderTable orders={filteredOrders} />
                      </div>
                    </div>
                  )}

                  {showReceipts && (
                    <div>
                      <div style={css.sectionTitle}>
                        <span>💳</span>
                        <span>التحصيلات المؤكدة بواسطته ({filteredReceipts.length})</span>
                      </div>
                      <div style={css.innerTableWrapper}>
                        <ReceiptTable receipts={filteredReceipts} />
                      </div>
                    </div>
                  )}
                </>
              )}
            </>
          )}
        </div>
      </div>
    </>
  )
}

// ─────────────────────────────────────────────────────────────
// MobileRepCard
// ─────────────────────────────────────────────────────────────

function MobileRepCard({
  row,
  onClick,
}: {
  row: RepCreditCommitmentRow
  onClick: () => void
}) {
  const isUnass = row.is_unassigned
  return (
    <div
      style={css.mobileCard(isUnass)}
      onClick={onClick}
      role="button"
      tabIndex={0}
      onKeyDown={e => { if (e.key === 'Enter') onClick() }}
    >
      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
        {isUnass ? (
          <span style={css.unassignedBadge}>⚠ غير مسند</span>
        ) : (
          <span style={{ fontWeight: 700, fontSize: 'var(--text-base)', color: 'var(--text-primary)' }}>
            {row.rep_name}
          </span>
        )}
        {row.overdue_customers_count > 0 && (
          <span style={css.badge('var(--color-danger-light)', 'var(--color-danger)')}>
            {row.overdue_customers_count} متأخر
          </span>
        )}
      </div>

      <div style={css.mobileCardGrid}>
        <div style={css.mobileCardField}>
          <span style={css.mobileCardLabel}>محفظة المتابعة</span>
          <span style={{ ...css.mobileCardValue, color: 'var(--color-info)' }}>
            {fmt(row.portfolio_balance)}
          </span>
        </div>
        <div style={css.mobileCardField}>
          <span style={css.mobileCardLabel}>العملاء</span>
          <span style={css.mobileCardValue}>
            {row.customers_count} (<span style={{ color: 'var(--color-info)' }}>{row.customers_with_balance}</span> بأرصدة)
          </span>
        </div>
        {!isUnass && (
          <>
            <div style={css.mobileCardField}>
              <span style={css.mobileCardLabel}>المديونية المنشأة</span>
              <span style={{ ...css.mobileCardValue, color: 'var(--color-danger)' }}>
                {fmt(row.created_debt)}
              </span>
            </div>
            <div style={css.mobileCardField}>
              <span style={css.mobileCardLabel}>التحصيلات</span>
              <span style={{ ...css.mobileCardValue, color: 'var(--color-success)' }}>
                {fmt(row.confirmed_collections)}
              </span>
            </div>
          </>
        )}
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Main Page
// ─────────────────────────────────────────────────────────────

export default function RepCreditCommitmentPage() {
  const isMobile = useIsMobile()
  const [selectedRow, setSelectedRow] = useState<RepCreditCommitmentRow | null>(null)
  const [hoveredId, setHoveredId] = useState<string | null>(null)
  const [pageFilters, setPageFilters] = useState<PageFilters>(DEFAULT_PAGE_FILTERS)
  const [showPageAdvanced, setShowPageAdvanced] = useState(false)
  const [paper, setPaper] = useState<'a4-landscape' | 'a4-portrait'>('a4-landscape')

  const { data, isLoading, error } = useQuery({
    queryKey:  ['rep-credit-commitment'],
    queryFn:   getRepCreditCommitmentReport,
    staleTime: 5 * 60_000,
  })

  const handleRowClick = useCallback((row: RepCreditCommitmentRow) => {
    setSelectedRow(row)
  }, [])

  const handleClose = useCallback(() => setSelectedRow(null), [])

  const allRows = data?.rows ?? []

  // تطبيق الفلاتر على الـ rows
  const rows    = useMemo(() => applyPageFilters(allRows, pageFilters), [allRows, pageFilters])
  const summary = useMemo(() => deriveFilteredSummary(rows), [rows])

  const rowKey = (r: RepCreditCommitmentRow) => r.rep_id ?? '__unassigned__'

  const updatePageFilter = useCallback(<K extends keyof PageFilters>(key: K, value: PageFilters[K]) => {
    setPageFilters(prev => ({ ...prev, [key]: value }))
  }, [])

  const pageFilterCount =
    (pageFilters.repSearch ? 1 : 0) +
    (!pageFilters.includeUnassigned ? 1 : 0) +
    (pageFilters.overdueOnly ? 1 : 0) +
    (pageFilters.portfolioMin ? 1 : 0) + (pageFilters.portfolioMax ? 1 : 0) +
    (pageFilters.createdDebtMin ? 1 : 0) + (pageFilters.createdDebtMax ? 1 : 0) +
    (pageFilters.collectionsMin ? 1 : 0) + (pageFilters.collectionsMax ? 1 : 0) +
    (pageFilters.sortBy !== 'none' ? 1 : 0)

  const printParams = pageFiltersToParams(pageFilters)

  return (
    <>
      <style>{`
        @keyframes shimmer {
          0%   { background-position: 200% 0; }
          100% { background-position: -200% 0; }
        }
        .cm-pager-btn {
          padding: 7px 14px;
          border: 1px solid var(--border-primary);
          border-radius: 8px;
          background: var(--bg-surface);
          color: var(--text-primary);
          font-family: var(--font-sans);
          font-size: var(--text-xs);
          font-weight: 600;
          cursor: pointer;
          min-height: 32px;
          transition: background 0.15s;
        }
        .cm-pager-btn:hover { background: var(--bg-surface-2); }
      `}</style>

      <div style={css.page} dir="rtl">

        {/* ── Page Header ── */}
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', flexWrap: 'wrap', gap: 'var(--space-3)' }}>
          <div>
            <h1 style={css.pageTitle}>التزام مسؤولي المحافظ الائتمانية</h1>
            <p style={css.pageSubtitle}>
              تحليل محافظ المتابعة، المديونية المنشأة، والتحصيلات لكل مسؤول محفظة
            </p>
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <select
              value={paper}
              onChange={e => setPaper(e.target.value as 'a4-landscape' | 'a4-portrait')}
              title="اختر مقاس الورقة للطباعة"
              style={{
                padding: '6px 10px', fontSize: '13px',
                border: '1px solid var(--border-primary)', borderRadius: '4px', background: '#fff'
              }}
            >
              <option value="a4-landscape">📄 A4 بالعرض</option>
              <option value="a4-portrait">📄 A4 بالطول</option>
            </select>
            {/* زر الطباعة للصفحة الرئيسية */}
            <DocumentActions
              kind="rep-credit-commitment-report"
              entityId="all"
              params={printParams}
              paperProfileId={paper}
              compact={true}
            />
          </div>
        </div>

        {/* ── فلاتر الصفحة الرئيسية ── */}
        <div style={css.filterBar}>
          <div style={css.filterRow}>
            {/* بحث المندوب */}
            <div style={{ position: 'relative', flex: '1 1 200px' }}>
              <span style={{
                position: 'absolute', insetInlineStart: 9,
                top: '50%', transform: 'translateY(-50%)',
                color: 'var(--text-muted)', fontSize: '0.8rem', pointerEvents: 'none',
              }}>🔍</span>
              <input
                type="text"
                placeholder="بحث باسم المسؤول..."
                value={pageFilters.repSearch}
                onChange={e => updatePageFilter('repSearch', e.target.value)}
                className="form-input"
                style={{ paddingInlineStart: 29, width: '100%', fontSize: 'var(--text-sm)' }}
              />
            </div>

            {/* ترتيب */}
            <select
              value={pageFilters.sortBy}
              onChange={e => updatePageFilter('sortBy', e.target.value as PageFilters['sortBy'])}
              className="form-input"
              style={{ minWidth: 160 }}
            >
              <option value="none">الترتيب الافتراضي</option>
              <option value="portfolio_desc">المحفظة (تنازلياً)</option>
              <option value="created_debt_desc">المديونية (تنازلياً)</option>
              <option value="collections_desc">التحصيلات (تنازلياً)</option>
              <option value="overdue_desc">المتأخرون (تنازلياً)</option>
              <option value="rep_name_asc">الاسم (أبجدي)</option>
            </select>

            {/* المتأخرون فقط */}
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 'var(--text-sm)', cursor: 'pointer', flexShrink: 0 }}>
              <input
                type="checkbox"
                checked={pageFilters.overdueOnly}
                onChange={e => updatePageFilter('overdueOnly', e.target.checked)}
              />
              <span>المتأخرون فقط</span>
            </label>

            {/* إظهار غير مسند */}
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: 'var(--text-sm)', cursor: 'pointer', flexShrink: 0 }}>
              <input
                type="checkbox"
                checked={pageFilters.includeUnassigned}
                onChange={e => updatePageFilter('includeUnassigned', e.target.checked)}
              />
              <span>إظهار "غير مسند"</span>
            </label>

            {/* زر الفلاتر الرقمية */}
            <button
              onClick={() => setShowPageAdvanced(v => !v)}
              className="cm-pager-btn"
              style={{
                flexShrink: 0,
                display: 'flex',
                alignItems: 'center',
                gap: 4,
                background: showPageAdvanced ? 'var(--color-primary-light)' : 'var(--bg-surface)',
                borderColor: showPageAdvanced ? 'var(--color-primary)' : 'var(--border-primary)',
                color: showPageAdvanced ? 'var(--color-primary)' : 'var(--text-secondary)',
              }}
            >
              ⚙ نطاقات
              {pageFilterCount > 0 && (
                <span style={{
                  background: 'var(--color-primary)', color: '#fff',
                  borderRadius: 99, padding: '1px 5px', fontSize: '0.6rem', fontWeight: 800,
                }}>{pageFilterCount}</span>
              )}
            </button>

            {/* إعادة تعيين */}
            {pageFilterCount > 0 && (
              <button
                onClick={() => setPageFilters(DEFAULT_PAGE_FILTERS)}
                className="cm-pager-btn"
                style={{ flexShrink: 0, color: 'var(--color-danger)', borderColor: 'var(--color-danger)' }}
              >
                ✕ تعيين
              </button>
            )}
          </div>

          {/* ── الفلاتر الرقمية المتقدمة ── */}
          {showPageAdvanced && (
            <div style={{
              borderTop: '1px solid var(--border-primary)',
              paddingTop: 'var(--space-3)',
              display: 'grid',
              gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))',
              gap: 'var(--space-3)',
            }}>
              {/* نطاق المحفظة */}
              <div>
                <div style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
                  محفظة المتابعة (ج.م)
                </div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <input type="number" min="0" placeholder="من" dir="ltr"
                    value={pageFilters.portfolioMin}
                    onChange={e => updatePageFilter('portfolioMin', e.target.value)}
                    className="form-input" style={{ width: '50%', fontSize: 'var(--text-xs)' }} />
                  <input type="number" min="0" placeholder="إلى" dir="ltr"
                    value={pageFilters.portfolioMax}
                    onChange={e => updatePageFilter('portfolioMax', e.target.value)}
                    className="form-input" style={{ width: '50%', fontSize: 'var(--text-xs)' }} />
                </div>
              </div>

              {/* نطاق المديونية */}
              <div>
                <div style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
                  المديونية المنشأة (ج.م)
                </div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <input type="number" min="0" placeholder="من" dir="ltr"
                    value={pageFilters.createdDebtMin}
                    onChange={e => updatePageFilter('createdDebtMin', e.target.value)}
                    className="form-input" style={{ width: '50%', fontSize: 'var(--text-xs)' }} />
                  <input type="number" min="0" placeholder="إلى" dir="ltr"
                    value={pageFilters.createdDebtMax}
                    onChange={e => updatePageFilter('createdDebtMax', e.target.value)}
                    className="form-input" style={{ width: '50%', fontSize: 'var(--text-xs)' }} />
                </div>
              </div>

              {/* نطاق التحصيلات */}
              <div>
                <div style={{ fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
                  التحصيلات المؤكدة (ج.م)
                </div>
                <div style={{ display: 'flex', gap: 6 }}>
                  <input type="number" min="0" placeholder="من" dir="ltr"
                    value={pageFilters.collectionsMin}
                    onChange={e => updatePageFilter('collectionsMin', e.target.value)}
                    className="form-input" style={{ width: '50%', fontSize: 'var(--text-xs)' }} />
                  <input type="number" min="0" placeholder="إلى" dir="ltr"
                    value={pageFilters.collectionsMax}
                    onChange={e => updatePageFilter('collectionsMax', e.target.value)}
                    className="form-input" style={{ width: '50%', fontSize: 'var(--text-xs)' }} />
                </div>
              </div>
            </div>
          )}
        </div>

        {/* ── KPI Cards skeleton ── */}
        {isLoading && (
          <div style={css.kpiGrid}>
            {[1, 2, 3, 4].map(i => (
              <div key={i} style={{
                ...css.kpiCard('#e2e8f0'),
                height: '6rem',
                background: 'var(--bg-surface-2)',
                animation: 'shimmer 1.5s infinite',
              }} />
            ))}
          </div>
        )}

        {/* ── KPI Cards (مشتقة من الـ rows المفلترة) ── */}
        {!isLoading && rows.length > 0 && (
          <>
            <div style={css.kpiGrid}>
              <div style={css.kpiCard('var(--color-primary)')}>
                <span style={css.kpiLabel}>مسؤولو المحافظ</span>
                <span style={css.kpiValue('var(--color-primary)')}>{summary.totalReps}</span>
                <span style={css.kpiSub}>لديهم عملاء بأرصدة فعلية</span>
              </div>

              <div style={css.kpiCard('var(--color-info)')}>
                <span style={css.kpiLabel}>إجمالي محافظ المتابعة</span>
                <span style={css.kpiValue('var(--color-info)')}>{fmt(summary.totalPortfolio)}</span>
                <span style={css.kpiSub}>يشمل الأرصدة الافتتاحية</span>
              </div>

              <div style={css.kpiCard('var(--color-danger)')}>
                <span style={css.kpiLabel}>إجمالي المديونية المنشأة</span>
                <span style={css.kpiValue('var(--color-danger)')}>{fmt(summary.totalCreatedDebt)}</span>
                <span style={css.kpiSub}>فواتير مسلَّمة صافيها {'>'} 0</span>
              </div>

              <div style={css.kpiCard('var(--color-success)')}>
                <span style={css.kpiLabel}>إجمالي التحصيلات المؤكدة</span>
                <span style={css.kpiValue('var(--color-success)')}>{fmt(summary.totalConfirmedCollections)}</span>
                <span style={css.kpiSub}>إيصالات confirmed فقط</span>
              </div>
            </div>

            {/* Unassigned warning */}
            {summary.hasUnassigned && (
              <div style={css.warningBanner}>
                <span style={{ fontSize: '1.4rem', flexShrink: 0 }}>⚠</span>
                <div style={css.warningText}>
                  <strong>أرصدة بدون مسؤول متابعة:</strong>{' '}
                  يوجد رصيد قدره <strong>{fmt(summary.unassignedBalance)}</strong> لدى
                  عملاء غير مسندين لأي مسؤول.
                  انقر على صف "غير مسند" في الجدول أدناه لعرض قائمة هؤلاء العملاء.
                </div>
              </div>
            )}
          </>
        )}

        {/* ── Error ── */}
        {error && (
          <div style={css.errorBanner}>
            حدث خطأ عند تحميل التقرير. يرجى إعادة المحاولة.
          </div>
        )}

        {/* ── مؤشر الفلترة ── */}
        {!isLoading && allRows.length > 0 && allRows.length !== rows.length && (
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', textAlign: 'center' }}>
            يُعرض <strong style={{ color: 'var(--text-primary)' }}>{rows.length}</strong> من {allRows.length} مسؤول
          </div>
        )}

        {/* ── Mobile Cards ── */}
        {isMobile && (
          <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-3)' }}>
            {isLoading && <Skeleton rows={5} />}
            {!isLoading && rows.length === 0 && (
              <div style={css.emptyRow}>لا توجد بيانات مطابقة للفلتر</div>
            )}
            {rows.map(row => (
              <MobileRepCard
                key={rowKey(row)}
                row={row}
                onClick={() => handleRowClick(row)}
              />
            ))}
          </div>
        )}

        {/* ── Desktop Table ── */}
        {!isMobile && (
          <div style={css.tableWrapper}>
            <table style={css.table}>
              <thead>
                <tr>
                  <th style={css.th}>المسؤول</th>
                  <th style={{ ...css.th, textAlign: 'center' }}>العملاء</th>
                  <th style={{ ...css.th, textAlign: 'center' }}>بأرصدة</th>
                  <th style={{ ...css.th, textAlign: 'center' }}>متأخرون</th>
                  <th style={css.th}>محفظة المتابعة</th>
                  <th style={css.th}>المديونية المنشأة</th>
                  <th style={css.th}>التحصيلات</th>
                </tr>
              </thead>
              <tbody>
                {isLoading && (
                  <tr>
                    <td colSpan={7}><Skeleton rows={5} /></td>
                  </tr>
                )}
                {!isLoading && rows.length === 0 && (
                  <tr>
                    <td colSpan={7} style={{ ...css.td, textAlign: 'center', color: 'var(--text-muted)' }}>
                      لا توجد بيانات مطابقة للفلتر
                    </td>
                  </tr>
                )}

                {rows.map(row => {
                  const key     = rowKey(row)
                  const isHover = hoveredId === key
                  const isUnass = row.is_unassigned

                  return (
                    <tr
                      key={key}
                      style={{
                        cursor: 'pointer',
                        transition: 'background var(--transition-fast)',
                        background: isUnass
                          ? isHover ? 'var(--color-warning-light)'  : 'transparent'
                          : isHover ? 'var(--bg-hover)'             : 'transparent',
                        borderRight: isUnass ? '3px solid var(--color-warning)' : '3px solid transparent',
                      }}
                      onClick={() => handleRowClick(row)}
                      onMouseEnter={() => setHoveredId(key)}
                      onMouseLeave={() => setHoveredId(null)}
                    >
                      <td style={css.td}>
                        {isUnass ? (
                          <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
                            <span style={css.unassignedBadge}>⚠ غير مسند</span>
                            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                              عملاء بلا مسؤول
                            </span>
                          </span>
                        ) : (
                          <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                            {row.rep_name}
                          </span>
                        )}
                      </td>
                      <td style={{ ...css.td, textAlign: 'center', fontWeight: 600 }}>
                        {row.customers_count}
                      </td>
                      <td style={{ ...css.td, textAlign: 'center', fontWeight: 600, color: 'var(--color-info)' }}>
                        {row.customers_with_balance}
                      </td>
                      <td style={{ ...css.td, textAlign: 'center' }}>
                        {row.overdue_customers_count > 0 ? (
                          <span style={css.badge('var(--color-danger-light)', 'var(--color-danger)')}>
                            {row.overdue_customers_count}
                          </span>
                        ) : (
                          <span style={{ color: 'var(--color-success)', fontWeight: 600 }}>—</span>
                        )}
                      </td>
                      <td style={{ ...css.td, fontWeight: 700, color: 'var(--color-info)' }}>
                        {fmt(row.portfolio_balance)}
                      </td>
                      <td style={css.td}>
                        {isUnass ? (
                          <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>لا ينطبق</span>
                        ) : (
                          <span style={{ fontWeight: 600, color: row.created_debt > 0 ? 'var(--color-danger)' : 'var(--text-secondary)' }}>
                            {fmt(row.created_debt)}
                          </span>
                        )}
                      </td>
                      <td style={css.td}>
                        {isUnass ? (
                          <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-xs)' }}>لا ينطبق</span>
                        ) : (
                          <span style={{ fontWeight: 600, color: 'var(--color-success)' }}>
                            {fmt(row.confirmed_collections)}
                          </span>
                        )}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}

        {/* ── Detail Drawer ── */}
        {selectedRow && (
          <RepDetailDrawer
            repId={selectedRow.rep_id}
            repName={selectedRow.rep_name}
            isUnassigned={selectedRow.is_unassigned}
            onClose={handleClose}
          />
        )}
      </div>
    </>
  )
}
