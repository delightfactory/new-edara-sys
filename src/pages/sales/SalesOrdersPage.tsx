import { useState, useMemo, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { ShoppingCart, Plus, Eye, Loader2, CheckCircle2, Zap } from 'lucide-react'
import { useSalesOrders, useSalesStats, useProfiles, useGovernorates, useCities } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { useFilterState } from '@/hooks/useFilterState'
import { useMobileInfiniteList } from '@/hooks/useIntersectionObserver'
import { useDeviceMode } from '@/hooks/useDeviceMode'
import type { SalesOrder, SalesOrderStatus } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import FilterBar from '@/components/shared/FilterBar'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import StatePanel from '@/components/patterns/StatePanel'
import SmartTransferDialog from '@/components/sales/SmartTransferDialog'
import {
  SALES_ORDER_STATUS_LABELS,
  SalesOrderCard,
  SalesOrderStatusBadge,
  SalesOrdersKpiGrid,
  selectSalesOrdersCollectionState,
} from '@/components/sales/SalesOrdersListPresentation'

const PAYMENT_LABELS: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
const PAYMENT_VARIANTS: Record<string, 'success' | 'warning' | 'info'> = { cash: 'success', credit: 'warning', mixed: 'info' }

// حالات "منتجة" — مُكتملة تجارياً
const PRODUCTIVE_STATUSES: SalesOrderStatus[] = ['confirmed', 'partially_delivered', 'delivered', 'completed']

const STATUS_OPTIONS = [
  { value: 'draft', label: 'مسودة' },
  { value: 'confirmed', label: 'مؤكد' },
  { value: 'partially_delivered', label: 'مسلّم جزئياً' },
  { value: 'delivered', label: 'مُسلّم' },
  { value: 'completed', label: 'مكتمل' },
  { value: 'cancelled', label: 'ملغي' },
]

const PAYMENT_TERMS_OPTIONS = [
  { value: 'cash', label: 'نقدي' },
  { value: 'credit', label: 'آجل' },
  { value: 'mixed', label: 'مختلط' },
]

const PAGE_SIZE = 25

export default function SalesOrdersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const device = useDeviceMode()
  const [smartTransferOpen, setSmartTransferOpen] = useState(false)

  // ── Filters (URL sync — Back يُستعيد الفلاتر تلقائياً) ──────────────────
  const { filters, setFilter, setFilters, reset, activeCount, filterKey } = useFilterState({
    defaults: {
      search: '',
      status: '',
      repId: '',
      paymentTerms: '',
      governorateId: '',
      cityId: '',
      dateFrom: '',
      dateTo: '',
    },
    urlSync: true,
  })

  const { data: cities = [] } = useCities(filters.governorateId || undefined)

  const handleGovChange = useCallback((govId: string) => {
    setFilters({ governorateId: govId, cityId: '' } as any)
  }, [setFilters])

  // ── Pagination ────────────────────────────────────────────────────────────
  const [desktopPage, setDesktopPage] = useState(1)
  const [mobilePage, setMobilePage] = useState(1)

  useEffect(() => {
    setDesktopPage(1)
    setMobilePage(1)
  }, [filterKey])

  const filterParams = useMemo(() => ({
    search: filters.search || undefined,
    status: filters.status as SalesOrderStatus | undefined || undefined,
    repId: filters.repId || undefined,
    paymentTerms: filters.paymentTerms || undefined,
    governorateId: filters.governorateId || undefined,
    cityId: filters.cityId || undefined,
    dateFrom: filters.dateFrom || undefined,
    dateTo: filters.dateTo || undefined,
  }), [filters])

  // ── Remote data ───────────────────────────────────────────────────────────
  const { data: reps = [] } = useProfiles()
  const { data: governorates = [] } = useGovernorates()

  const repOptions = useMemo(() => reps.map(r => ({ value: r.id, label: r.full_name })), [reps])
  const govOptions = useMemo(() => governorates.map(g => ({ value: g.id, label: g.name })), [governorates])
  const cityOptions = useMemo(() => cities.map(c => ({ value: c.id, label: c.name })), [cities])

  // Global KPI (لا يتأثر بالفلاتر — يمثل الصورة الكاملة)
  const { data: globalStats } = useSalesStats()

  // Desktop / Tablet query — preserves existing numbered-pagination semantics.
  const desktopParams = useMemo(() => ({ ...filterParams, page: desktopPage, pageSize: PAGE_SIZE }), [filterParams, desktopPage])
  const { data: desktopResult, isLoading: desktopLoading } = useSalesOrders(desktopParams)
  const desktopOrders = desktopResult?.data ?? []
  const totalPages = desktopResult?.totalPages ?? 1
  const totalCount = desktopResult?.count ?? 0

  // Mobile query — preserves existing accumulated infinite-list semantics.
  const mobileParams = useMemo(() => ({ ...filterParams, page: mobilePage, pageSize: PAGE_SIZE }), [filterParams, mobilePage])
  const { data: mobileResult, isLoading: mobileLoading } = useSalesOrders(mobileParams)
  const mobileData = mobileResult?.data ?? []
  const hasMoreMobile = mobileData.length === PAGE_SIZE

  const handleLoadMore = useCallback(() => {
    if (!mobileLoading && hasMoreMobile) setMobilePage(p => p + 1)
  }, [mobileLoading, hasMoreMobile])

  const { accumulated: mobileOrders, sentinelRef } = useMobileInfiniteList<SalesOrder>({
    data: mobileData,
    pageSize: PAGE_SIZE,
    loading: mobileLoading,
    resetKey: filterKey,
    hasMore: hasMoreMobile,
    onLoadMore: handleLoadMore,
  })

  const collectionState = selectSalesOrdersCollectionState({
    device,
    desktopItems: desktopOrders,
    mobileItems: mobileOrders,
    desktopLoading,
    mobileLoading,
  })

  // ── Smart FilterBar Stats ─────────────────────────────────────────────────
  const allOnOnePage = totalCount <= PAGE_SIZE

  const filterStats = useMemo(() => {
    type V = 'default' | 'success' | 'warning' | 'danger' | 'info'
    const parts: string[] = []

    const selectedStatus = filters.status as SalesOrderStatus | ''
    if (selectedStatus) parts.push(SALES_ORDER_STATUS_LABELS[selectedStatus])

    if (filters.paymentTerms) parts.push(PAYMENT_LABELS[filters.paymentTerms] || filters.paymentTerms)

    const repName = filters.repId
      ? reps.find(r => r.id === filters.repId)?.full_name?.split(' ')[0] ?? ''
      : ''
    if (repName) parts.push(repName)

    const govName = filters.governorateId
      ? governorates.find(g => g.id === filters.governorateId)?.name ?? ''
      : ''
    if (govName) parts.push(`في ${govName}`)
    if (filters.cityId && cities.length > 0) {
      const cityName = cities.find(c => c.id === filters.cityId)?.name ?? ''
      if (cityName) parts.push(cityName)
    }

    if (filters.dateFrom && filters.dateTo) {
      parts.push(`${new Date(filters.dateFrom).toLocaleDateString('ar-EG-u-nu-latn')} → ${new Date(filters.dateTo).toLocaleDateString('ar-EG-u-nu-latn')}`)
    } else if (filters.dateFrom) {
      parts.push(`من ${new Date(filters.dateFrom).toLocaleDateString('ar-EG-u-nu-latn')}`)
    } else if (filters.dateTo) {
      parts.push(`حتى ${new Date(filters.dateTo).toLocaleDateString('ar-EG-u-nu-latn')}`)
    }

    const contextLabel = parts.length > 0 ? `طلب ${parts.join(' · ')}` : 'طلب'
    const primaryVariant: V = selectedStatus === 'cancelled' ? 'danger'
      : selectedStatus === 'confirmed' ? 'info'
        : selectedStatus === 'delivered' || selectedStatus === 'completed' ? 'success'
          : 'default'

    const result: { label: string; value: string | number; variant: V; loading?: boolean }[] = [
      {
        label: contextLabel,
        value: totalCount.toLocaleString('en-US'),
        variant: primaryVariant,
        loading: desktopLoading,
      },
    ]

    // Sub-stats remain page-owned and retain the existing Desktop-page projection.
    if (desktopOrders.length > 0 && !desktopLoading) {
      const productive = desktopOrders.filter(o => PRODUCTIVE_STATUSES.includes(o.status))
      const uniqueCustomers = new Set(desktopOrders.map(o => o.customer_id).filter(Boolean)).size

      if (uniqueCustomers > 1) {
        result.push({ label: 'عميل', value: uniqueCustomers.toLocaleString('en-US'), variant: 'default' })
      }

      if (!filters.status) {
        const cancelledCount = desktopOrders.filter(o => o.status === 'cancelled').length
        if (cancelledCount > 0) {
          result.push({ label: 'ملغي', value: cancelledCount.toLocaleString('en-US'), variant: 'danger' })
        }
      }

      if (!filters.status) {
        const confirmedCount = productive.length
        const confirmedRatio = desktopOrders.length > 0 ? confirmedCount / desktopOrders.length : 0
        if (confirmedCount > 0 && confirmedRatio < 1) {
          result.push({ label: 'منتج', value: confirmedCount.toLocaleString('en-US'), variant: 'success' })
        }
      }
    }

    return result
  }, [
    filters.status,
    filters.paymentTerms,
    filters.repId,
    filters.governorateId,
    filters.cityId,
    filters.dateFrom,
    filters.dateTo,
    totalCount,
    desktopLoading,
    desktopOrders,
    reps,
    governorates,
    cities,
    allOnOnePage,
  ])

  // ── Dense Desktop table columns ───────────────────────────────────────────
  const columns = [
    {
      key: 'order_number',
      label: 'رقم الطلب',
      render: (o: SalesOrder) => (
        <>
          <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)', fontFamily: 'monospace' }} dir="ltr">{o.order_number}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
            {new Date(o.order_date).toLocaleDateString('ar-EG-u-nu-latn')}
          </div>
        </>
      ),
    },
    {
      key: 'customer',
      label: 'العميل',
      render: (o: SalesOrder) => (
        <>
          <div style={{ fontWeight: 500, fontSize: 'var(--text-sm)' }}>{o.customer?.name || '—'}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{o.customer?.code}</div>
        </>
      ),
    },
    {
      key: 'rep',
      label: 'المندوب',
      hideOnMobile: true,
      render: (o: SalesOrder) => o.rep?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span>,
    },
    {
      key: 'total',
      label: 'الإجمالي',
      hideOnMobile: true,
      render: (o: SalesOrder) => (
        <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
          {formatNumber(o.total_amount)} <span style={{ fontWeight: 400, color: 'var(--text-muted)', fontSize: '0.7rem' }}>ج.م</span>
        </span>
      ),
    },
    {
      key: 'paid',
      label: 'المدفوع / المتبقي',
      hideOnMobile: true,
      render: (o: SalesOrder) => {
        const collected = o.paid_amount + o.returned_amount
        const outstanding = Math.max(0, o.total_amount - collected)
        const paidRatio = o.total_amount > 0 ? collected / o.total_amount : 0
        const color = paidRatio >= 1 ? 'var(--color-success)'
          : paidRatio > 0 ? 'var(--color-warning)'
            : 'var(--text-muted)'

        return (
          <div>
            <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <span style={{ fontVariantNumeric: 'tabular-nums', color, fontSize: 'var(--text-xs)', fontWeight: 600 }}>
                {formatNumber(o.paid_amount)}
              </span>
              {outstanding > 0 && (
                <span style={{ fontSize: '10px', color: 'var(--color-warning)', fontVariantNumeric: 'tabular-nums' }}>
                  ({formatNumber(outstanding)} متبقي)
                </span>
              )}
            </div>
            <div style={{ marginTop: 3, height: 3, borderRadius: 9999, background: 'var(--border-subtle)', overflow: 'hidden', width: 80 }}>
              <div style={{
                width: `${Math.min(paidRatio * 100, 100)}%`,
                height: '100%',
                background: paidRatio >= 1 ? 'var(--color-success)' : 'var(--color-warning)',
                borderRadius: 9999,
                transition: 'width 0.4s ease',
              }} />
            </div>
          </div>
        )
      },
    },
    {
      key: 'payment_terms',
      label: 'الدفع',
      hideOnMobile: true,
      render: (o: SalesOrder) => o.payment_terms
        ? <Badge variant={PAYMENT_VARIANTS[o.payment_terms] || 'neutral'}>{PAYMENT_LABELS[o.payment_terms] || o.payment_terms}</Badge>
        : <span style={{ color: 'var(--text-muted)' }}>—</span>,
    },
    {
      key: 'status',
      label: 'الحالة',
      render: (o: SalesOrder) => <SalesOrderStatusBadge status={o.status} />,
    },
    {
      key: 'actions',
      label: '',
      width: 50,
      render: (o: SalesOrder) => (
        <div onClick={e => e.stopPropagation()}>
          <Button
            variant="ghost"
            size="sm"
            aria-label={`عرض الطلب ${o.order_number}`}
            icon={<Eye size={14} />}
            onClick={() => navigate(`/sales/orders/${o.id}`)}
          />
        </div>
      ),
    },
  ]

  const renderOrderCard = (order: SalesOrder, mode: 'mobile' | 'tablet') => {
    const collected = order.paid_amount + order.returned_amount
    const outstanding = Math.max(0, order.total_amount - collected)
    const paidRatio = order.total_amount > 0 ? collected / order.total_amount : 0
    const phone = order.customer?.mobile || order.customer?.phone
    const hasMap = !!(order.customer?.latitude && order.customer?.longitude)

    return (
      <SalesOrderCard
        key={order.id}
        mode={mode}
        summary={{
          customerName: order.customer?.name || '—',
          customerCode: order.customer?.code,
          orderNumber: order.order_number,
          orderDate: new Date(order.order_date).toLocaleDateString('ar-EG-u-nu-latn'),
          status: order.status,
          total: `${formatNumber(order.total_amount)} ج.م`,
          paid: `${formatNumber(order.paid_amount)} ج.م`,
          outstanding: outstanding > 0 ? `${formatNumber(outstanding)} ج.م` : undefined,
          paymentTerms: order.payment_terms ? PAYMENT_LABELS[order.payment_terms] || order.payment_terms : undefined,
          representative: order.rep?.full_name,
          paidPercent: order.total_amount > 0 ? Math.round(paidRatio * 100) : undefined,
          progressPercent: order.total_amount > 0 ? paidRatio * 100 : undefined,
        }}
        onOpen={() => navigate(`/sales/orders/${order.id}`)}
        onMap={hasMap
          ? () => window.open(`https://www.google.com/maps/search/?api=1&query=${order.customer?.latitude},${order.customer?.longitude}`, '_blank')
          : undefined}
        onCall={phone
          ? () => { window.location.href = `tel:${phone}` }
          : undefined}
      />
    )
  }

  const renderNumberedPagination = () => {
    if (totalPages <= 1) return null

    return (
      <div className="pagination" style={{ padding: 'var(--space-4)' }} data-sales-tablet-pagination>
        <span className="pagination-info">
          صفحة {desktopPage} من {totalPages} ({totalCount})
        </span>
        <div className="pagination-buttons">
          <button
            className="pagination-btn"
            disabled={desktopPage <= 1}
            onClick={() => setDesktopPage(desktopPage - 1)}
            aria-label="الصفحة السابقة"
          >
            ‹
          </button>
          {Array.from({ length: Math.min(totalPages, 5) }, (_, i) => {
            const num = desktopPage <= 3 ? i + 1 : desktopPage + i - 2
            if (num < 1 || num > totalPages) return null
            return (
              <button
                key={num}
                className={`pagination-btn${num === desktopPage ? ' active' : ''}`}
                onClick={() => setDesktopPage(num)}
                aria-current={num === desktopPage ? 'page' : undefined}
              >
                {num}
              </button>
            )
          })}
          <button
            className="pagination-btn"
            disabled={desktopPage >= totalPages}
            onClick={() => setDesktopPage(desktopPage + 1)}
            aria-label="الصفحة التالية"
          >
            ›
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="أوامر البيع"
        subtitle={desktopLoading ? '...' : `${totalCount.toLocaleString('en-US')} طلب`}
        actions={
          <div style={{ display: 'flex', gap: 'var(--space-2)', alignItems: 'center' }}>
            {can('sales.orders.create') && (
              <Button
                id="smart-transfer-btn"
                className="desktop-only-btn"
                variant="secondary"
                icon={<Zap size={15} />}
                onClick={() => setSmartTransferOpen(true)}
                title="إنشاء تحويل ذكي من المسودات"
              >
                التحويل الذكي
              </Button>
            )}
            {can('sales.orders.create') && (
              <Button
                icon={<Plus size={16} />}
                onClick={() => navigate('/sales/orders/new')}
                className="desktop-only-btn"
              >
                طلب جديد
              </Button>
            )}
          </div>
        }
      />

      {globalStats && <SalesOrdersKpiGrid stats={globalStats} />}

      <FilterBar
        title="فلاتر أوامر البيع"
        activeCount={activeCount}
        onReset={reset}
        stats={filterStats}
      >
        <FilterBar.Search
          value={filters.search}
          onChange={v => setFilter('search', v)}
          placeholder="بحث برقم الطلب أو اسم أو هاتف العميل..."
          fullWidth
        />

        <FilterBar.Select
          label="حالة الطلب"
          value={filters.status}
          onChange={v => setFilter('status', v)}
          options={STATUS_OPTIONS}
          allLabel="كل الحالات"
        />

        <FilterBar.Select
          label="طريقة الدفع"
          value={filters.paymentTerms}
          onChange={v => setFilter('paymentTerms', v)}
          options={PAYMENT_TERMS_OPTIONS}
          allLabel="كل طرق الدفع"
        />

        <FilterBar.Select
          label="المندوب"
          value={filters.repId}
          onChange={v => setFilter('repId', v)}
          options={repOptions}
          allLabel="كل المناديب"
        />

        <FilterBar.Select
          label="محافظة العميل"
          value={filters.governorateId}
          onChange={handleGovChange}
          options={govOptions}
          allLabel="كل المحافظات"
        />

        {filters.governorateId && cityOptions.length > 0 && (
          <FilterBar.Select
            label="مدينة العميل"
            value={filters.cityId}
            onChange={v => setFilter('cityId', v)}
            options={cityOptions}
            allLabel="كل المدن"
          />
        )}

        <FilterBar.DateRange
          label="تاريخ الطلب"
          from={filters.dateFrom}
          to={filters.dateTo}
          onFromChange={v => setFilter('dateFrom', v)}
          onToChange={v => setFilter('dateTo', v)}
          fullWidth
        />
      </FilterBar>

      <ResponsiveCollection<SalesOrder>
        items={collectionState.items}
        loading={collectionState.loading && collectionState.items.length === 0}
        loadingState={device === 'desktop' ? (
          <div className="edara-card" style={{ overflow: 'auto' }}>
            <DataTable<SalesOrder> columns={columns} data={[]} loading />
          </div>
        ) : (
          <div className={device === 'tablet' ? 'sales-v2-card-grid' : 'mobile-card-list'} aria-label="جاري تحميل أوامر البيع">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '55%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '35%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        )}
        emptyState={(
          <StatePanel
            kind="empty"
            icon={<ShoppingCart size={40} />}
            title="لا توجد أوامر بيع"
            description={device === 'mobile' ? undefined : 'لم يتم العثور على طلبات مطابقة للفلاتر'}
            action={device !== 'mobile' && can('sales.orders.create') ? (
              <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}>
                طلب جديد
              </Button>
            ) : undefined}
          />
        )}
        renderDesktop={items => (
          <div className="edara-card" style={{ overflow: 'auto' }}>
            <DataTable<SalesOrder>
              columns={columns}
              data={items}
              loading={false}
              onRowClick={o => navigate(`/sales/orders/${o.id}`)}
              page={desktopPage}
              totalPages={totalPages}
              totalCount={totalCount}
              onPageChange={setDesktopPage}
            />
          </div>
        )}
        renderTablet={items => (
          <>
            <div className="sales-v2-card-grid">
              {items.map(order => renderOrderCard(order, 'tablet'))}
            </div>
            {renderNumberedPagination()}
          </>
        )}
        renderMobile={items => (
          <div className="mobile-card-list">
            {items.map(order => renderOrderCard(order, 'mobile'))}

            <div ref={sentinelRef} style={{ height: 8, flexShrink: 0 }} />

            {mobileLoading && mobileOrders.length > 0 && (
              <div className="infinite-loading">
                <Loader2 size={18} className="spin-icon" />
                <span>جاري تحميل المزيد...</span>
              </div>
            )}
            {!mobileLoading && !hasMoreMobile && mobileOrders.length > 0 && (
              <div className="infinite-end">
                <CheckCircle2 size={16} />
                <span>جميع الطلبات ({mobileOrders.length.toLocaleString('en-US')})</span>
              </div>
            )}
          </div>
        )}
      />

      {can('sales.orders.create') && (
        <Button
          id="smart-transfer-fab"
          className="smart-transfer-fab"
          variant="primary"
          size="lg"
          touchTarget
          icon={<Zap size={22} />}
          onClick={() => setSmartTransferOpen(true)}
          aria-label="التحويل الذكي"
          title="التحويل الذكي"
        />
      )}

      <SmartTransferDialog
        open={smartTransferOpen}
        onClose={() => setSmartTransferOpen(false)}
        onSuccess={(_id) => {
          // يمكن التوجه لصفحة التحويلات بعد الإنشاء
          // navigate(`/inventory/transfers/${_id}`)
        }}
      />

      <style>{`
        @media (max-width: 768px) {
          .desktop-only-btn { display: none; }
        }

        .sales-v2-card-grid {
          display: grid;
          grid-template-columns: repeat(auto-fit, minmax(min(100%, 22rem), 1fr));
          gap: var(--space-3);
          padding-block-end: var(--space-4);
        }

        .mobile-card-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          padding: 0 0 var(--space-4);
        }

        .infinite-loading {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          padding: var(--space-4);
          color: var(--text-muted);
          font-size: var(--text-sm);
        }

        .spin-icon {
          animation: spin 1s linear infinite;
          color: var(--color-primary);
        }

        @keyframes spin {
          from { transform: rotate(0deg); }
          to { transform: rotate(360deg); }
        }

        .infinite-end {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          color: var(--color-success);
          font-size: var(--text-sm);
          font-weight: 600;
          background: var(--color-success-light);
          border-radius: var(--radius-lg);
          margin-top: var(--space-2);
        }

        .smart-transfer-fab {
          display: none;
          position: fixed;
          bottom: calc(var(--bottom-nav-height, 64px) + var(--space-4) + 64px);
          inset-inline-end: var(--space-4);
          z-index: 155;
          width: 50px;
          height: 50px;
          border-radius: 50%;
          box-shadow: 0 6px 20px rgba(37, 99, 235, .32);
          align-items: center;
          justify-content: center;
        }

        @media (max-width: 768px) {
          .smart-transfer-fab { display: flex; }
        }
      `}</style>
    </div>
  )
}
