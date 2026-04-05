import { useState, useMemo, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import {
  ShoppingCart, Plus, Eye, FileText, TrendingUp, DollarSign,
  CheckCircle, Truck, AlertCircle, Loader2, CheckCircle2,
} from 'lucide-react'
import { useSalesOrders, useSalesStats, useProfiles, useGovernorates, useCities } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { useFilterState } from '@/hooks/useFilterState'
import { useMobileInfiniteList } from '@/hooks/useIntersectionObserver'
import type { SalesOrder, SalesOrderStatus, City } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import FilterBar from '@/components/shared/FilterBar'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'

// ── Constants ────────────────────────────────────────────────────────────────

const STATUS_LABELS: Record<SalesOrderStatus, string> = {
  draft: 'مسودة', confirmed: 'مؤكد', partially_delivered: 'مسلّم جزئياً',
  delivered: 'مُسلّم', completed: 'مكتمل', cancelled: 'ملغي',
}
const STATUS_VARIANTS: Record<SalesOrderStatus, 'neutral' | 'primary' | 'info' | 'success' | 'danger' | 'warning'> = {
  draft: 'neutral', confirmed: 'primary', partially_delivered: 'info',
  delivered: 'success', completed: 'success', cancelled: 'danger',
}
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

// ── Component ─────────────────────────────────────────────────────────────────

export default function SalesOrdersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

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

  // المدن — reactive على governorateId من الـ URL (يعمل عند Back button أيضاً)
  const { data: cities = [] } = useCities(filters.governorateId || undefined)

  // تغيير المحافظة: كلا التحديثين في setSearchParams واحد (يمنع React 18 batching race)
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

  // Desktop query
  const desktopParams = useMemo(() => ({ ...filterParams, page: desktopPage, pageSize: PAGE_SIZE }), [filterParams, desktopPage])
  const { data: desktopResult, isLoading: desktopLoading } = useSalesOrders(desktopParams)
  const desktopOrders = desktopResult?.data ?? []
  const totalPages = desktopResult?.totalPages ?? 1
  const totalCount = desktopResult?.count ?? 0

  // Mobile query
  const mobileParams = useMemo(() => ({ ...filterParams, page: mobilePage, pageSize: PAGE_SIZE }), [filterParams, mobilePage])
  const { data: mobileResult, isLoading: mobileLoading } = useSalesOrders(mobileParams)
  const mobileData = mobileResult?.data ?? []
  const hasMoreMobile = mobileData.length === PAGE_SIZE

  const handleLoadMore = useCallback(() => {
    if (!mobileLoading && hasMoreMobile) setMobilePage(p => p + 1)
  }, [mobileLoading, hasMoreMobile])

  const { accumulated: mobileOrders, sentinelRef } = useMobileInfiniteList<SalesOrder>({
    data: mobileData, pageSize: PAGE_SIZE, loading: mobileLoading,
    resetKey: filterKey, hasMore: hasMoreMobile, onLoadMore: handleLoadMore,
  })

  // ── Smart FilterBar Stats ─────────────────────────────────────────────────
  //
  // مبادئ الإحصاءات الذكية:
  //   1. totalCount دائماً من الـ server (دقيق 100%)
  //   2. label الإجمالي يعكس سياق الفلاتر المفعّلة (الوضوح للمستخدم)
  //   3. الأرقام المالية (المبيعات، المتبقي) تُحسب فقط عندما كل البيانات في صفحة واحدة
  //   4. لا sub-stat يكرر ما هو واضح من الفلتر المفعّل

  const allOnOnePage = totalCount <= PAGE_SIZE

  const filterStats = useMemo(() => {
    type V = 'default' | 'success' | 'warning' | 'danger' | 'info'

    // ── 1. Label يعكس مجموع الفلاتر المفعّلة ─────────────────────────
    const parts: string[] = []

    // حالة الطلب
    const selectedStatus = filters.status as SalesOrderStatus | ''
    if (selectedStatus) parts.push(STATUS_LABELS[selectedStatus])

    // طريقة الدفع
    if (filters.paymentTerms) parts.push(PAYMENT_LABELS[filters.paymentTerms] || filters.paymentTerms)

    // المندوب
    const repName = filters.repId
      ? reps.find(r => r.id === filters.repId)?.full_name?.split(' ')[0] ?? ''
      : ''
    if (repName) parts.push(repName)

    // الموقع الجغرافي
    const govName = filters.governorateId
      ? governorates.find(g => g.id === filters.governorateId)?.name ?? ''
      : ''
    if (govName) parts.push(`في ${govName}`)
    if (filters.cityId && cities.length > 0) {
      const cityName = cities.find(c => c.id === filters.cityId)?.name ?? ''
      if (cityName) parts.push(cityName)
    }

    // نطاق التاريخ
    if (filters.dateFrom && filters.dateTo) {
      parts.push(`${new Date(filters.dateFrom).toLocaleDateString('ar-EG-u-nu-latn')} → ${new Date(filters.dateTo).toLocaleDateString('ar-EG-u-nu-latn')}`)
    } else if (filters.dateFrom) {
      parts.push(`من ${new Date(filters.dateFrom).toLocaleDateString('ar-EG-u-nu-latn')}`)
    } else if (filters.dateTo) {
      parts.push(`حتى ${new Date(filters.dateTo).toLocaleDateString('ar-EG-u-nu-latn')}`)
    }

    // Label نهائي — "طلب" + السياق
    const contextLabel = parts.length > 0 ? `طلب ${parts.join(' · ')}` : 'طلب'
    const primaryVariant: V = selectedStatus === 'cancelled' ? 'danger'
      : selectedStatus === 'confirmed' ? 'info'
        : selectedStatus === 'delivered' || selectedStatus === 'completed' ? 'success'
          : 'default'

    const result: { label: string; value: string | number; variant: V; loading?: boolean }[] = [
      {
        label: contextLabel,
        value: totalCount.toLocaleString('ar-EG'),
        variant: primaryVariant,
        loading: desktopLoading,
      },
    ]

    // ── 2. Sub-stats مالية (دائماً عن desktopOrders = الصفحة الحالية) ──────
    // السبب الجذري: allOnOnePage كان شرطاً خاطئاً.
    // قبلاً: count:estimated كان يُعيد 0 → allOnOnePage=true دائماً (صدفة).
    // الآن: count:exact صحيح → allOnOnePage=false → لا تظهر stats (الخطـأ).
    //
    // الحل الصحيح: sub-stats تعرض دائماً لـ desktopOrders (الصفحة المعروضة).
    // البيانات صادقة: primaryStat يُظهر الإجمالي الصحيح (487 طلب)،
    // والقيم المالية تعكس الصفحة → لا تناقض ولا تضليل.
    if (desktopOrders.length > 0 && !desktopLoading) {
      const productive = desktopOrders.filter(o => PRODUCTIVE_STATUSES.includes(o.status))

      // عملاء فريدون — عدد صحيح 100% (unique ids في الصفحة الحالية)
      const uniqueCustomers = new Set(
        desktopOrders.map(o => o.customer_id).filter(Boolean)
      ).size
      if (uniqueCustomers > 1) {
        result.push({ label: 'عميل', value: uniqueCustomers.toLocaleString('ar-EG'), variant: 'default' })
      }

      // ملغي — فقط عند غياب فلتر الحالة
      if (!filters.status) {
        const cancelledCount = desktopOrders.filter(o => o.status === 'cancelled').length
        if (cancelledCount > 0) {
          result.push({ label: 'ملغي', value: cancelledCount.toLocaleString('ar-EG'), variant: 'danger' })
        }
      }

      // مؤكد — كإشارة نوعية لجودة الطلبات في هذه النتيجة
      if (!filters.status) {
        const confirmedCount = productive.length
        const confirmedRatio = desktopOrders.length > 0 ? confirmedCount / desktopOrders.length : 0
        if (confirmedCount > 0 && confirmedRatio < 1) {
          result.push({ label: 'منتج', value: confirmedCount.toLocaleString('ar-EG'), variant: 'success' })
        }
      }
    }




    return result
  }, [
    filters.status, filters.paymentTerms, filters.repId,
    filters.governorateId, filters.cityId, filters.dateFrom, filters.dateTo,
    totalCount, desktopLoading, desktopOrders,
    reps, governorates, cities, allOnOnePage,
  ])

  // ── Table columns ─────────────────────────────────────────────────────────
  const columns = [
    {
      key: 'order_number', label: 'رقم الطلب',
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
      key: 'customer', label: 'العميل',
      render: (o: SalesOrder) => (
        <>
          <div style={{ fontWeight: 500, fontSize: 'var(--text-sm)' }}>{o.customer?.name || '—'}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }} dir="ltr">{o.customer?.code}</div>
        </>
      ),
    },
    {
      key: 'rep', label: 'المندوب', hideOnMobile: true,
      render: (o: SalesOrder) => o.rep?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span>,
    },
    {
      key: 'total', label: 'الإجمالي', hideOnMobile: true,
      render: (o: SalesOrder) => (
        <span style={{ fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>
          {formatNumber(o.total_amount)} <span style={{ fontWeight: 400, color: 'var(--text-muted)', fontSize: '0.7rem' }}>ج.م</span>
        </span>
      ),
    },
    {
      key: 'paid', label: 'المدفوع / المتبقي', hideOnMobile: true,
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
            {/* نسبة المدفوع — شريط بصري */}
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
      key: 'payment_terms', label: 'الدفع', hideOnMobile: true,
      render: (o: SalesOrder) => o.payment_terms
        ? <Badge variant={PAYMENT_VARIANTS[o.payment_terms] || 'neutral'}>{PAYMENT_LABELS[o.payment_terms] || o.payment_terms}</Badge>
        : <span style={{ color: 'var(--text-muted)' }}>—</span>,
    },
    {
      key: 'status', label: 'الحالة',
      render: (o: SalesOrder) => <Badge variant={STATUS_VARIANTS[o.status]}>{STATUS_LABELS[o.status]}</Badge>,
    },
    {
      key: 'actions', label: '', width: 50,
      render: (o: SalesOrder) => (
        <div onClick={e => e.stopPropagation()}>
          <Button variant="ghost" size="sm" onClick={() => navigate(`/sales/orders/${o.id}`)}>
            <Eye size={14} />
          </Button>
        </div>
      ),
    },
  ]

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="أوامر البيع"
        subtitle={desktopLoading ? '...' : `${totalCount.toLocaleString('ar-EG')} طلب`}
        actions={can('sales.orders.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}
            className="desktop-only-btn">
            طلب جديد
          </Button>
        ) : undefined}
      />

      {/* ── KPI Cards (إجمالي عام — لا تتأثر بالفلاتر) ── */}
      {globalStats && (
        <div className="kpi-grid">
          <div className="kpi-card kpi-primary">
            <div className="kpi-icon"><TrendingUp size={16} /></div>
            <div className="kpi-body">
              <div className="kpi-label">إجمالي المبيعات</div>
              <div className="kpi-value" dir="ltr">{formatNumber(globalStats.totalSales)} <span className="kpi-unit">ج.م</span></div>
            </div>
          </div>
          <div className="kpi-card">
            <div className="kpi-icon kpi-neutral"><FileText size={16} /></div>
            <div className="kpi-body">
              <div className="kpi-label">مسودة</div>
              <div className="kpi-value">{(globalStats.statusCounts.draft ?? 0).toLocaleString('ar-EG')}</div>
            </div>
          </div>
          <div className="kpi-card">
            <div className="kpi-icon kpi-info"><CheckCircle size={16} /></div>
            <div className="kpi-body">
              <div className="kpi-label">مؤكد</div>
              <div className="kpi-value">{(globalStats.statusCounts.confirmed ?? 0).toLocaleString('ar-EG')}</div>
            </div>
          </div>
          <div className="kpi-card">
            <div className="kpi-icon kpi-success"><Truck size={16} /></div>
            <div className="kpi-body">
              <div className="kpi-label">مُسلّم</div>
              <div className="kpi-value">{(globalStats.statusCounts.delivered ?? 0).toLocaleString('ar-EG')}</div>
            </div>
          </div>
          <div className="kpi-card">
            <div className="kpi-icon kpi-danger"><AlertCircle size={16} /></div>
            <div className="kpi-body">
              <div className="kpi-label">ملغي</div>
              <div className="kpi-value">{(globalStats.statusCounts.cancelled ?? 0).toLocaleString('ar-EG')}</div>
            </div>
          </div>
        </div>
      )}

      {/* ── FilterBar ────────────────────────────────────────────────────── */}
      <FilterBar
        title="فلاتر أوامر البيع"
        activeCount={activeCount}
        onReset={reset}
        stats={filterStats}
      >
        {/* بحث: رقم الطلب + اسم/كود/هاتف العميل */}
        <FilterBar.Search
          value={filters.search}
          onChange={v => setFilter('search', v)}
          placeholder="بحث برقم الطلب أو اسم أو هاتف العميل..."
          fullWidth
        />

        {/* حالة الطلب */}
        <FilterBar.Select
          label="حالة الطلب"
          value={filters.status}
          onChange={v => setFilter('status', v)}
          options={STATUS_OPTIONS}
          allLabel="كل الحالات"
        />

        {/* طريقة الدفع */}
        <FilterBar.Select
          label="طريقة الدفع"
          value={filters.paymentTerms}
          onChange={v => setFilter('paymentTerms', v)}
          options={PAYMENT_TERMS_OPTIONS}
          allLabel="كل طرق الدفع"
        />

        {/* المندوب */}
        <FilterBar.Select
          label="المندوب"
          value={filters.repId}
          onChange={v => setFilter('repId', v)}
          options={repOptions}
          allLabel="كل المناديب"
        />

        {/* المحافظة */}
        <FilterBar.Select
          label="محافظة العميل"
          value={filters.governorateId}
          onChange={handleGovChange}
          options={govOptions}
          allLabel="كل المحافظات"
        />

        {/* المدينة — تظهر فقط عند اختيار محافظة */}
        {filters.governorateId && cityOptions.length > 0 && (
          <FilterBar.Select
            label="مدينة العميل"
            value={filters.cityId}
            onChange={v => setFilter('cityId', v)}
            options={cityOptions}
            allLabel="كل المدن"
          />
        )}

        {/* نطاق التاريخ */}
        <FilterBar.DateRange
          label="تاريخ الطلب"
          from={filters.dateFrom}
          to={filters.dateTo}
          onFromChange={v => setFilter('dateFrom', v)}
          onToChange={v => setFilter('dateTo', v)}
          fullWidth
        />
      </FilterBar>

      {/* ══ DESKTOP: Numbered Pagination ══════════════════════════════════ */}
      <div className="sales-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<SalesOrder>
          columns={columns}
          data={desktopOrders}
          loading={desktopLoading}
          onRowClick={o => navigate(`/sales/orders/${o.id}`)}
          emptyIcon={<ShoppingCart size={48} />}
          emptyTitle="لا توجد أوامر بيع"
          emptyText="لم يتم العثور على طلبات مطابقة للفلاتر"
          emptyAction={can('sales.orders.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/sales/orders/new')}>طلب جديد</Button>
          ) : undefined}
          page={desktopPage}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setDesktopPage}
        />
      </div>

      {/* ══ MOBILE: Infinite Scroll ════════════════════════════════════════ */}
      <div className="sales-card-view">
        {mobileLoading && mobileOrders.length === 0 ? (
          <div className="mobile-card-list">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '55%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '35%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : mobileOrders.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <ShoppingCart size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا توجد أوامر بيع</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {mobileOrders.map(o => {
              const collected = o.paid_amount + o.returned_amount
              const outstanding = Math.max(0, o.total_amount - collected)
              const paidRatio = o.total_amount > 0 ? collected / o.total_amount : 0
              return (
                <DataCard
                  key={o.id}
                  title={o.customer?.name || '—'}
                  subtitle={
                    <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>
                      {o.order_number}
                    </span>
                  }
                  badge={<Badge variant={STATUS_VARIANTS[o.status]}>{STATUS_LABELS[o.status]}</Badge>}
                  leading={
                    <div style={{
                      width: 40, height: 40, borderRadius: 'var(--radius-md)',
                      background: 'var(--bg-accent)', display: 'flex', alignItems: 'center', justifyContent: 'center',
                    }}>
                      <ShoppingCart size={18} style={{ color: 'var(--color-primary)' }} />
                    </div>
                  }
                  metadata={[
                    { label: 'التاريخ', value: new Date(o.order_date).toLocaleDateString('ar-EG-u-nu-latn') },
                    { label: 'الإجمالي', value: `${formatNumber(o.total_amount)} ج.م`, highlight: true },
                    { label: 'المدفوع', value: `${formatNumber(o.paid_amount)} ج.م` },
                    ...(outstanding > 0 ? [{ label: 'المتبقي', value: `${formatNumber(outstanding)} ج.م` }] : []),
                    ...(o.payment_terms ? [{ label: 'الدفع', value: PAYMENT_LABELS[o.payment_terms] || o.payment_terms }] : []),
                    ...(o.rep?.full_name ? [{ label: 'المندوب', value: o.rep.full_name }] : []),
                  ]}
                  actions={
                    <div style={{ display: 'flex', flexDirection: 'column', gap: 8, width: '100%' }}>
                      {/* شريط نسبة السداد */}
                      {o.total_amount > 0 && (
                        <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                          <div style={{ flex: 1, height: 4, borderRadius: 9999, background: 'var(--border-subtle)', overflow: 'hidden' }}>
                            <div style={{
                              width: `${Math.min(paidRatio * 100, 100)}%`,
                              height: '100%',
                              background: paidRatio >= 1 ? 'var(--color-success)' : paidRatio > 0 ? 'var(--color-warning)' : 'var(--border-subtle)',
                              borderRadius: 9999, transition: 'width 0.4s',
                            }} />
                          </div>
                          <span style={{ fontSize: '10px', color: 'var(--text-muted)', minWidth: 28 }} dir="ltr">
                            {Math.round(paidRatio * 100)}%
                          </span>
                        </div>
                      )}
                      <Button variant="secondary" size="sm" style={{ width: '100%', justifyContent: 'center' }}
                        onClick={() => navigate(`/sales/orders/${o.id}`)}>
                        <Eye size={14} /> عرض التفاصيل
                      </Button>
                    </div>
                  }
                  onClick={() => navigate(`/sales/orders/${o.id}`)}
                />
              )
            })}

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
                <span>جميع الطلبات ({mobileOrders.length.toLocaleString('ar-EG')})</span>
              </div>
            )}
          </div>
        )}
      </div>

      <style>{`
        /* ── KPI Grid ─────────────────────────────────────────────────── */
        .kpi-grid {
          display: grid;
          grid-template-columns: 2fr 1fr 1fr 1fr 1fr;
          gap: var(--space-3);
          margin-bottom: var(--space-4);
        }
        .kpi-card {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          background: var(--bg-surface);
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-xl);
          box-shadow: 0 1px 3px rgba(0,0,0,.04);
          transition: box-shadow 0.2s, transform 0.2s;
        }
        .kpi-card:hover { box-shadow: 0 4px 12px rgba(0,0,0,.08); transform: translateY(-1px); }
        .kpi-primary {
          background: linear-gradient(135deg, var(--color-primary), rgba(37,99,235,.8));
          border-color: transparent;
        }
        .kpi-primary .kpi-label { color: rgba(255,255,255,.75) !important; }
        .kpi-primary .kpi-value { color: #fff !important; }
        .kpi-primary .kpi-unit  { color: rgba(255,255,255,.7) !important; }
        .kpi-icon {
          width: 36px; height: 36px;
          border-radius: var(--radius-lg);
          background: var(--bg-accent);
          display: flex; align-items: center; justify-content: center;
          color: var(--color-primary);
          flex-shrink: 0;
        }
        .kpi-primary .kpi-icon { background: rgba(255,255,255,.18); color: #fff; }
        .kpi-neutral { background: var(--neutral-100) !important; color: var(--text-muted) !important; }
        .kpi-info    { background: var(--color-info-light, rgba(2,132,199,.1)) !important; color: var(--color-info, #0284c7) !important; }
        .kpi-success { background: var(--color-success-light) !important; color: var(--color-success) !important; }
        .kpi-danger  { background: var(--color-danger-light) !important;  color: var(--color-danger) !important; }
        .kpi-body { min-width: 0; }
        .kpi-label  { font-size: 10px; font-weight: 600; color: var(--text-muted); text-transform: uppercase; letter-spacing: .04em; margin-bottom: 2px; }
        .kpi-value  { font-size: var(--text-lg); font-weight: 800; font-variant-numeric: tabular-nums; color: var(--text-primary); line-height: 1.1; }
        .kpi-unit   { font-size: var(--text-xs); font-weight: 500; color: var(--text-muted); }

        /* ── Desktop/Mobile split ─────────────────────────────────────── */
        .sales-table-view { display: block; }
        .sales-card-view  { display: none; }

        @media (max-width: 768px) {
          .sales-table-view { display: none; }
          .sales-card-view  { display: block; }
          .desktop-only-btn { display: none; }
          .kpi-grid {
            grid-template-columns: 1fr 1fr;
            gap: var(--space-2);
          }
          .kpi-primary { grid-column: 1 / -1; }
          .kpi-card { padding: var(--space-2) var(--space-3); }
          .kpi-value { font-size: var(--text-base); }
        }

        /* ── Mobile infinite scroll ───────────────────────────────────── */
        .mobile-card-list {
          display: flex; flex-direction: column; gap: var(--space-3); padding: 0 0 var(--space-4);
        }
        .infinite-loading {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-2); padding: var(--space-4);
          color: var(--text-muted); font-size: var(--text-sm);
        }
        .spin-icon { animation: spin 1s linear infinite; color: var(--color-primary); }
        @keyframes spin { from { transform: rotate(0deg); } to { transform: rotate(360deg); } }
        .infinite-end {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-2); padding: var(--space-3) var(--space-4);
          color: var(--color-success); font-size: var(--text-sm); font-weight: 600;
          background: var(--color-success-light); border-radius: var(--radius-lg);
          margin-top: var(--space-2);
        }
      `}</style>
    </div>
  )
}
