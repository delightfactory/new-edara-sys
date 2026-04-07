import { useState, useMemo, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Users, ToggleLeft, ToggleRight, Eye, Phone, Loader2, CheckCircle2 } from 'lucide-react'
import { toggleCustomerActive } from '@/lib/services/customers'
import { getCities } from '@/lib/services/geography'
import { useCustomers, useGovernorates, useProfiles, useInvalidate, useCities } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { useFilterState } from '@/hooks/useFilterState'
import { useMobileInfiniteList } from '@/hooks/useIntersectionObserver'
import type { Customer } from '@/lib/types/master-data'
import { formatNumber } from '@/lib/utils/format'
import FilterBar from '@/components/shared/FilterBar'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import CustomerCreditChip from '@/components/shared/CustomerCreditChip'

const typeLabels:    Record<string, string>                      = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' }
const typeBadge:    Record<string, 'neutral' | 'info' | 'primary'> = { retail: 'neutral', wholesale: 'info', distributor: 'primary' }
const paymentLabels: Record<string, string>                      = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
const paymentBadge:  Record<string, 'success' | 'warning' | 'info'> = { cash: 'success', credit: 'warning', mixed: 'info' }

const TYPE_OPTIONS = [
  { value: 'retail',      label: 'تجزئة'  },
  { value: 'wholesale',   label: 'جملة'    },
  { value: 'distributor', label: 'موزع'   },
]

const STATUS_OPTIONS = [
  { value: 'all',      label: 'كل الحالات' },
  { value: 'inactive', label: 'معطل'  },
]

const CUSTOMER_DEFAULTS = {
  search:       '',
  type:         '',
  governorateId: '',
  cityId:       '',
  repId:        '',
  status:       '',
}

const PAGE_SIZE = 25

export default function CustomersPage() {
  const navigate   = useNavigate()
  const can        = useAuthStore(s => s.can)
  const invalidate = useInvalidate()

  // ── Filters via useFilterState ─────────────────────────────────────
  const { filters, setFilter, setFilters, reset, activeCount, filterKey } = useFilterState({
    defaults: CUSTOMER_DEFAULTS,
    urlSync: true,
  })

  // المدن — reactive على governorateId من الـ URL (يعمل عند Back button أيضاً)
  const { data: cities = [] } = useCities(filters.governorateId || undefined)

  // ── Pagination ─────────────────────────────────────────────────────
  const [desktopPage, setDesktopPage] = useState(1)
  const [mobilePage,  setMobilePage]  = useState(1)

  const [confirmTarget, setConfirmTarget] = useState<Customer | null>(null)
  const [toggling,      setToggling]      = useState(false)

  // ── Remote data ────────────────────────────────────────────────────
  const { data: governorates = [] } = useGovernorates()
  const { data: reps = [] }         = useProfiles()

  const filterParams = useMemo(() => ({
    search:        filters.search        || undefined,
    type:          filters.type          || undefined,
    governorateId: filters.governorateId || undefined,
    cityId:        filters.cityId        || undefined,
    repId:         filters.repId         || undefined,
    isActive:      filters.status === 'all' ? undefined : (filters.status === 'inactive' ? false : true),
  }), [filters])

  // إعادة ضبط الصفحات عند تغيير الفلاتر
  useEffect(() => {
    setDesktopPage(1)
    setMobilePage(1)
  }, [filterKey])

  // Desktop
  const desktopParams = useMemo(() => ({ ...filterParams, page: desktopPage, pageSize: PAGE_SIZE }), [filterParams, desktopPage])
  const { data: desktopResult, isLoading: desktopLoading } = useCustomers(desktopParams)
  const desktopCustomers = desktopResult?.data ?? []
  const totalCount       = desktopResult?.count ?? 0
  const totalPages       = desktopResult?.totalPages ?? 1

  // Mobile
  const mobileParams = useMemo(() => ({ ...filterParams, page: mobilePage, pageSize: PAGE_SIZE }), [filterParams, mobilePage])
  const { data: mobileResult, isLoading: mobileLoading } = useCustomers(mobileParams)
  const mobileData    = mobileResult?.data ?? []
  const hasMoreMobile = mobileData.length === PAGE_SIZE

  const handleLoadMore = useCallback(() => {
    if (!mobileLoading && hasMoreMobile) setMobilePage(p => p + 1)
  }, [mobileLoading, hasMoreMobile])

  const { accumulated: mobileCustomers, sentinelRef } = useMobileInfiniteList<Customer>({
    data:       mobileData,
    pageSize:   PAGE_SIZE,
    loading:    mobileLoading,
    resetKey:   filterKey,
    hasMore:    hasMoreMobile,
    onLoadMore: handleLoadMore,
  })

  // ── Geography: تحميل المدن عند اختيار محافظة ──────────────────────
  const handleGovChange = useCallback((govId: string) => {
    setFilters({ governorateId: govId, cityId: '' } as any)
  }, [setFilters])

  // ── Toggle active ──────────────────────────────────────────────────
  const handleToggle  = (c: Customer) => setConfirmTarget(c)
  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    setToggling(true)
    try {
      await toggleCustomerActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'إلغاء تفعيل'} العميل`)
      invalidate('customers')
    } catch { toast.error('فشلت العملية') }
    finally { setToggling(false); setConfirmTarget(null) }
  }

  // ── Options for FilterBar.Select ───────────────────────────────────
  const govOptions = useMemo(() =>
    governorates.map(g => ({ value: g.id, label: g.name })),
    [governorates]
  )
  const cityOptions = useMemo(() =>
    cities.map(c => ({ value: c.id, label: c.name })),
    [cities]
  )
  const repOptions = useMemo(() =>
    reps.map(r => ({ value: r.id, label: r.full_name })),
    [reps]
  )

  // ── Stats ذكية: totalCount من الـ server (دقيق 100%)
  // المنطق:
  //   1. label الإجمالي يعكس سياق الفلاتر المفعّلة
  //   2. Sub-stats تختفي إذا كان الفلتر يُكررها (لا قيمة مضافة)
  //   3. التوزيع الداخلي (نشط/آجل) يظهر فقط عندما البيانات في صفحة واحدة
  //      (لأن الحسابات من desktopCustomers تكون دقيقة 100% آنذاك)
  const allOnOnePage = totalCount <= PAGE_SIZE

  const filterStats = useMemo(() => {
    type StatVariant = 'default' | 'success' | 'warning' | 'danger' | 'info'

    // ── 1. Label + variant للـ stat الرئيسي ──────────────────────────
    let primaryLabel   = 'عميل'
    let primaryVariant: StatVariant = 'default'

    if (filters.status === '')         { primaryLabel = 'عميل نشط';  primaryVariant = 'success' }
    if (filters.status === 'inactive') { primaryLabel = 'عميل معطل'; primaryVariant = 'danger'  }
    if (filters.status === 'all')      { primaryLabel = 'عميل';      primaryVariant = 'default'  }

    // أضف سياق البعد الجغرافي إذا كان مُفعّلاً (يُغني عن كتابة اسم المحافظة)
    const govName  = filters.governorateId
      ? governorates.find(g => g.id === filters.governorateId)?.name ?? ''
      : ''
    const hasGeo   = Boolean(filters.governorateId || filters.cityId)
    const typeHint = filters.type === 'retail'      ? 'تجزئة'
                   : filters.type === 'wholesale'   ? 'جملة'
                   : filters.type === 'distributor' ? 'موزع'
                   : ''

    // بناء label إثرائي: "عميل نشط جملة في القاهرة"
    const parts: string[] = [primaryLabel]
    if (typeHint  && filters.type)    parts.push(typeHint)
    if (hasGeo    && govName)         parts.push(`في ${govName}`)
    primaryLabel = parts.join(' ')

    // ── 2. Stat الأساسي — دائماً من totalCount (server) ─────────────
    const result: ReturnType<typeof useMemo<any>> = [
      {
        label:   primaryLabel,
        value:   totalCount.toLocaleString('ar-EG'),
        variant: primaryVariant,
        loading: desktopLoading,
      },
    ]

    // ── 3. Sub-stats: التوزيع الداخلي (من desktopCustomers = الصفحة الحالية) ──
    // ملاحظة: البيانات من الصفحة الأولى دائماً — مفيدة للاستدلال السريع.
    // primaryStat يُظهر الإجمالي الدقيق من الـ server (totalCount).
    if (desktopCustomers.length > 0 && !desktopLoading) {
      const activeInPage   = desktopCustomers.filter(c =>  c.is_active).length
      const inactiveInPage = desktopCustomers.filter(c => !c.is_active).length
      const creditInPage   = desktopCustomers.filter(c => c.payment_terms === 'credit').length

      // نشط — اعرضه فقط إذا لا يوجد فلتر حالة
      if (!filters.status && activeInPage > 0 && activeInPage < desktopCustomers.length) {
        result.push({
          label:   'نشط',
          value:   activeInPage.toLocaleString('ar-EG'),
          variant: 'success' as const,
        })
      }

      // معطل — اعرضه فقط إذا لا يوجد فلتر حالة وكانت هناك معطّلون
      if (!filters.status && inactiveInPage > 0) {
        result.push({
          label:   'معطل',
          value:   inactiveInPage.toLocaleString('ar-EG'),
          variant: 'danger' as const,
        })
      }

      // آجل — دائماً مفيد
      if (creditInPage > 0) {
        result.push({
          label:   'آجل',
          value:   creditInPage.toLocaleString('ar-EG'),
          variant: 'warning' as const,
        })
      }
    }

    return result
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [
    filters.status, filters.type, filters.governorateId, filters.cityId,
    totalCount, desktopLoading, desktopCustomers, governorates,
  ])


  // ── Desktop table columns ──────────────────────────────────────────
  const columns = [
    {
      key: 'name', label: 'العميل',
      render: (c: Customer) => (
        <>
          <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{c.name}</div>
          <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', display: 'flex', gap: 'var(--space-2)', alignItems: 'center', flexWrap: 'wrap' }}>
            <span dir="ltr" style={{ fontFamily: 'monospace' }}>{c.code}</span>
            {c.mobile && <span dir="ltr">• {c.mobile}</span>}
          </div>
        </>
      ),
    },
    { key: 'type', label: 'النوع', hideOnMobile: true, render: (c: Customer) => <Badge variant={typeBadge[c.type] || 'neutral'}>{typeLabels[c.type] || c.type}</Badge> },
    {
      key: 'location', label: 'الموقع', hideOnMobile: true,
      render: (c: Customer) => (
        <>
          <div style={{ fontSize: 'var(--text-sm)' }}>{(c as any).governorate?.name || '—'}</div>
          {(c as any).city && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{(c as any).city.name}</div>}
        </>
      ),
    },
    { key: 'rep',    label: 'المندوب',     hideOnMobile: true, render: (c: Customer) => (c as any).assigned_rep?.full_name || <span style={{ color: 'var(--text-muted)' }}>—</span> },
    { key: 'payment',label: 'الدفع',       hideOnMobile: true, render: (c: Customer) => <Badge variant={paymentBadge[c.payment_terms as string] || 'neutral'}>{paymentLabels[c.payment_terms as string] || c.payment_terms}</Badge> },
    {
      key: 'credit', label: 'الائتمان المتاح', hideOnMobile: true,
      render: (c: Customer) => (
        <CustomerCreditChip
          payment_terms={c.payment_terms as string}
          credit_limit={c.credit_limit}
          credit_days={c.credit_days}
          current_balance={c.current_balance ?? 0}
          mode="compact"
        />
      ),
    },
    { key: 'status', label: 'الحالة', render: (c: Customer) => <Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge> },
    {
      key: 'actions', label: 'إجراءات', width: 100,
      render: (c: Customer) => (
        <div className="flex gap-1" onClick={e => e.stopPropagation()}>
          <Button variant="ghost" size="sm" title="عرض/تعديل" onClick={() => navigate(`/customers/${c.id}`)}>
            <Eye size={14} />
          </Button>
          {can('customers.update') && (
            <Button variant={c.is_active ? 'danger' : 'success'} size="sm"
              title={c.is_active ? 'تعطيل' : 'تفعيل'} onClick={() => handleToggle(c)}>
              {c.is_active ? <ToggleLeft size={14} /> : <ToggleRight size={14} />}
            </Button>
          )}
        </div>
      ),
    },
  ]

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="العملاء"
        subtitle={desktopLoading ? '...' : `${totalCount.toLocaleString('ar-EG')} عميل`}
        actions={can('customers.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}
            className="desktop-only-btn">
            إضافة عميل
          </Button>
        ) : undefined}
      />

      {/* ── FilterBar ────────────────────────────────────────────────── */}
      <FilterBar
        title="فلاتر العملاء"
        activeCount={activeCount}
        onReset={reset}
        stats={filterStats}
      >

        {/* البحث النصي — يمتد عرض كامل */}
        <FilterBar.Search
          value={filters.search}
          onChange={v => setFilter('search', v)}
          placeholder="بحث بالاسم أو الكود أو الهاتف..."
          fullWidth
        />

        {/* نوع العميل */}
        <FilterBar.Select
          label="نوع العميل"
          value={filters.type}
          onChange={v => setFilter('type', v)}
          options={TYPE_OPTIONS}
          allLabel="كل الأنواع"
        />

        {/* المحافظة */}
        <FilterBar.Select
          label="المحافظة"
          value={filters.governorateId}
          onChange={handleGovChange}
          options={govOptions}
          allLabel="كل المحافظات"
        />

        {/* المدينة — تظهر فقط عند اختيار محافظة */}
        {filters.governorateId && cityOptions.length > 0 && (
          <FilterBar.Select
            label="المدينة"
            value={filters.cityId}
            onChange={v => setFilter('cityId', v)}
            options={cityOptions}
            allLabel="كل المدن"
          />
        )}

        {/* المندوب */}
        <FilterBar.Select
          label="المندوب"
          value={filters.repId}
          onChange={v => setFilter('repId', v)}
          options={repOptions}
          allLabel="كل المناديب"
        />

        {/* الحالة */}
        <FilterBar.Select
          label="الحالة"
          value={filters.status}
          onChange={v => setFilter('status', v)}
          options={STATUS_OPTIONS}
          allLabel="نشط (افتراضي)"
        />
      </FilterBar>

      {/* ══════════════ DESKTOP: Numbered Pagination ════════════════ */}
      <div className="customers-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Customer>
          columns={columns}
          data={desktopCustomers}
          loading={desktopLoading}
          onRowClick={c => navigate(`/customers/${c.id}`)}
          rowStyle={c => ({ opacity: c.is_active ? 1 : 0.6 })}
          emptyIcon={<Users size={48} />}
          emptyTitle="لا يوجد عملاء"
          emptyText="لم يتم العثور على عملاء مطابقين للبحث"
          emptyAction={can('customers.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}>إضافة أول عميل</Button>
          ) : undefined}
          page={desktopPage}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setDesktopPage}
        />
      </div>

      {/* ══════════════ MOBILE: Infinite Scroll ═══════════════════ */}
      <div className="customers-card-view">
        {mobileLoading && mobileCustomers.length === 0 ? (
          <div className="mobile-card-list">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '60%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '40%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '80%' }} />
              </div>
            ))}
          </div>
        ) : mobileCustomers.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <Users size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد عملاء</p>
            <p className="empty-state-text">لم يتم العثور على عملاء مطابقين للبحث</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {mobileCustomers.map(c => (
              <DataCard
                key={c.id}
                title={c.name}
                subtitle={
                  <span style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-1)' }}>
                    <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem' }}>{c.code}</span>
                    {c.mobile && (
                      <>
                        <span>•</span>
                        <Phone size={11} />
                        <span dir="ltr">{c.mobile}</span>
                      </>
                    )}
                  </span>
                }
                badge={<Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge>}
                metadata={[
                  { label: 'نوع العميل',   value: typeLabels[c.type] || c.type },
                  { label: 'طريقة الدفع',  value: paymentLabels[c.payment_terms as string] || c.payment_terms },
                  ...((c as any).governorate?.name ? [{ label: 'المحافظة', value: (c as any).governorate.name }] : []),
                  ...((c as any).assigned_rep?.full_name ? [{ label: 'المندوب', value: (c as any).assigned_rep.full_name }] : []),
                  {
                    label: 'الائتمان',
                    value: (
                      <CustomerCreditChip
                        payment_terms={c.payment_terms as string}
                        credit_limit={c.credit_limit}
                        credit_days={c.credit_days}
                        current_balance={c.current_balance ?? 0}
                        mode="inline"
                      />
                    ),
                  },
                ]}
                actions={
                  <div className="flex gap-2" style={{ width: '100%' }}>
                    <Button variant="secondary" size="sm" onClick={() => navigate(`/customers/${c.id}`)}
                      style={{ flex: 1, justifyContent: 'center' }}>
                      <Eye size={14} /> عرض
                    </Button>
                    {can('customers.update') && (
                      <Button variant={c.is_active ? 'danger' : 'success'} size="sm"
                        onClick={() => handleToggle(c)}
                        style={{ flex: 1, justifyContent: 'center' }}>
                        {c.is_active ? <><ToggleLeft size={14} /> تعطيل</> : <><ToggleRight size={14} /> تفعيل</>}
                      </Button>
                    )}
                  </div>
                }
                onClick={() => navigate(`/customers/${c.id}`)}
              />
            ))}

            <div ref={sentinelRef} style={{ height: 8, flexShrink: 0 }} />

            {mobileLoading && mobileCustomers.length > 0 && (
              <div className="infinite-loading">
                <Loader2 size={18} className="spin-icon" />
                <span>جاري تحميل المزيد...</span>
              </div>
            )}

            {!mobileLoading && !hasMoreMobile && mobileCustomers.length > 0 && (
              <div className="infinite-end">
                <CheckCircle2 size={16} />
                <span>جميع العملاء ({mobileCustomers.length.toLocaleString('ar-EG')})</span>
              </div>
            )}
          </div>
        )}
      </div>

      {/* ── Confirm Modal ─────────────────────────────────────────── */}
      <ResponsiveModal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title={confirmTarget?.is_active ? 'تعطيل العميل' : 'تفعيل العميل'}
        disableOverlayClose={toggling}
        footer={
          <>
            <Button variant="secondary" onClick={() => setConfirmTarget(null)} disabled={toggling}>إلغاء</Button>
            <Button variant={confirmTarget?.is_active ? 'danger' : 'success'}
              onClick={executeToggle} disabled={toggling}>
              {toggling ? 'جاري التنفيذ...' : confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
            </Button>
          </>
        }
      >
        <p style={{ margin: 0, color: 'var(--text-secondary)', fontSize: 'var(--text-sm)', lineHeight: 1.7 }}>
          هل تريد {confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} العميل{' '}
          <strong style={{ color: 'var(--text-primary)' }}>"{confirmTarget?.name}"</strong>؟
        </p>
      </ResponsiveModal>

      <style>{`
        /* Desktop shows table, Mobile shows infinite cards */
        .customers-table-view { display: block; }
        .customers-card-view  { display: none; }

        @media (max-width: 768px) {
          .customers-table-view { display: none; }
          .customers-card-view  { display: block; }
          .desktop-only-btn     { display: none; }
        }

        .mobile-card-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          padding: 0 0 var(--space-4);
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
