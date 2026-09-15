import { useState, useMemo, useCallback, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, Users, ToggleLeft, ToggleRight, Eye, Phone, Loader2, CheckCircle2, MapPin, PhoneCall } from 'lucide-react'
import { toggleCustomerActive } from '@/lib/services/customers'
import { useCustomers, useGovernorates, useProfiles, useInvalidate, useCities } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { useFilterState } from '@/hooks/useFilterState'
import { useMobileInfiniteList } from '@/hooks/useIntersectionObserver'
import { useDeviceMode } from '@/hooks/useDeviceMode'
import type { Customer } from '@/lib/types/master-data'
import FilterBar from '@/components/shared/FilterBar'
import PageHeader from '@/components/shared/PageHeader'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import CustomerCreditChip from '@/components/shared/CustomerCreditChip'
import ResponsiveCollection from '@/components/patterns/ResponsiveCollection'
import StatePanel from '@/components/patterns/StatePanel'
import Card from '@/components/patterns/Card'
import './customers-v2.css'

const typeLabels: Record<string, string> = { retail: 'تجزئة', wholesale: 'جملة', distributor: 'موزع' }
const typeBadge: Record<string, 'neutral' | 'info' | 'primary'> = { retail: 'neutral', wholesale: 'info', distributor: 'primary' }
const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
const paymentBadge: Record<string, 'success' | 'warning' | 'info'> = { cash: 'success', credit: 'warning', mixed: 'info' }

const TYPE_OPTIONS = [
  { value: 'retail', label: 'تجزئة' },
  { value: 'wholesale', label: 'جملة' },
  { value: 'distributor', label: 'موزع' },
]

const STATUS_OPTIONS = [
  { value: 'all', label: 'كل الحالات' },
  { value: 'inactive', label: 'معطل' },
]

const CUSTOMER_DEFAULTS = {
  search: '',
  type: '',
  governorateId: '',
  cityId: '',
  repId: '',
  status: '',
}

const PAGE_SIZE = 25

export default function CustomersPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()
  const device = useDeviceMode()

  const { filters, setFilter, setFilters, reset, activeCount, filterKey } = useFilterState({
    defaults: CUSTOMER_DEFAULTS,
    urlSync: true,
  })

  const { data: cities = [] } = useCities(filters.governorateId || undefined)

  const [desktopPage, setDesktopPage] = useState(1)
  const [mobilePage, setMobilePage] = useState(1)

  const [confirmTarget, setConfirmTarget] = useState<Customer | null>(null)
  const [toggling, setToggling] = useState(false)

  const { data: governorates = [] } = useGovernorates()
  const { data: reps = [] } = useProfiles()

  const filterParams = useMemo(() => ({
    search: filters.search || undefined,
    type: filters.type || undefined,
    governorateId: filters.governorateId || undefined,
    cityId: filters.cityId || undefined,
    repId: filters.repId || undefined,
    isActive: filters.status === 'all' ? undefined : (filters.status === 'inactive' ? false : true),
  }), [filters])

  useEffect(() => {
    setDesktopPage(1)
    setMobilePage(1)
  }, [filterKey])

  // Desktop / Tablet data path — numbered pagination remains unchanged.
  const desktopParams = useMemo(
    () => ({ ...filterParams, page: desktopPage, pageSize: PAGE_SIZE }),
    [filterParams, desktopPage]
  )
  const { data: desktopResult, isLoading: desktopLoading } = useCustomers(desktopParams)
  const desktopCustomers = desktopResult?.data ?? []
  const totalCount = desktopResult?.count ?? 0
  const totalPages = desktopResult?.totalPages ?? 1

  // Mobile data path — infinite accumulation remains unchanged.
  const mobileParams = useMemo(
    () => ({ ...filterParams, page: mobilePage, pageSize: PAGE_SIZE }),
    [filterParams, mobilePage]
  )
  const { data: mobileResult, isLoading: mobileLoading } = useCustomers(mobileParams)
  const mobileData = mobileResult?.data ?? []
  const hasMoreMobile = mobileData.length === PAGE_SIZE

  const handleLoadMore = useCallback(() => {
    if (!mobileLoading && hasMoreMobile) setMobilePage(p => p + 1)
  }, [mobileLoading, hasMoreMobile])

  const { accumulated: mobileCustomers, sentinelRef } = useMobileInfiniteList<Customer>({
    data: mobileData,
    pageSize: PAGE_SIZE,
    loading: mobileLoading,
    resetKey: filterKey,
    hasMore: hasMoreMobile,
    onLoadMore: handleLoadMore,
  })

  const handleGovChange = useCallback((govId: string) => {
    setFilters({ governorateId: govId, cityId: '' } as any)
  }, [setFilters])

  const handleToggle = (c: Customer) => setConfirmTarget(c)
  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    setToggling(true)
    try {
      await toggleCustomerActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'إلغاء تفعيل'} العميل`)
      invalidate('customers')
    } catch {
      toast.error('فشلت العملية')
    } finally {
      setToggling(false)
      setConfirmTarget(null)
    }
  }

  const govOptions = useMemo(
    () => governorates.map(g => ({ value: g.id, label: g.name })),
    [governorates]
  )
  const cityOptions = useMemo(
    () => cities.map(c => ({ value: c.id, label: c.name })),
    [cities]
  )
  const repOptions = useMemo(
    () => reps.map(r => ({ value: r.id, label: r.full_name })),
    [reps]
  )

  const filterStats = useMemo(() => {
    type StatVariant = 'default' | 'success' | 'warning' | 'danger' | 'info'

    let primaryLabel = 'عميل'
    let primaryVariant: StatVariant = 'default'

    if (filters.status === '') {
      primaryLabel = 'عميل نشط'
      primaryVariant = 'success'
    }
    if (filters.status === 'inactive') {
      primaryLabel = 'عميل معطل'
      primaryVariant = 'danger'
    }
    if (filters.status === 'all') {
      primaryLabel = 'عميل'
      primaryVariant = 'default'
    }

    const govName = filters.governorateId
      ? governorates.find(g => g.id === filters.governorateId)?.name ?? ''
      : ''
    const hasGeo = Boolean(filters.governorateId || filters.cityId)
    const typeHint = filters.type === 'retail'
      ? 'تجزئة'
      : filters.type === 'wholesale'
        ? 'جملة'
        : filters.type === 'distributor'
          ? 'موزع'
          : ''

    const parts: string[] = [primaryLabel]
    if (typeHint && filters.type) parts.push(typeHint)
    if (hasGeo && govName) parts.push(`في ${govName}`)
    primaryLabel = parts.join(' ')

    const result: Array<{
      label: string
      value: string
      variant: StatVariant
      loading?: boolean
    }> = [
      {
        label: primaryLabel,
        value: totalCount.toLocaleString('en-US'),
        variant: primaryVariant,
        loading: desktopLoading,
      },
    ]

    if (desktopCustomers.length > 0 && !desktopLoading) {
      const activeInPage = desktopCustomers.filter(c => c.is_active).length
      const inactiveInPage = desktopCustomers.filter(c => !c.is_active).length
      const creditInPage = desktopCustomers.filter(c => c.payment_terms === 'credit').length

      if (!filters.status && activeInPage > 0 && activeInPage < desktopCustomers.length) {
        result.push({
          label: 'نشط',
          value: activeInPage.toLocaleString('en-US'),
          variant: 'success',
        })
      }

      if (!filters.status && inactiveInPage > 0) {
        result.push({
          label: 'معطل',
          value: inactiveInPage.toLocaleString('en-US'),
          variant: 'danger',
        })
      }

      if (creditInPage > 0) {
        result.push({
          label: 'آجل',
          value: creditInPage.toLocaleString('en-US'),
          variant: 'warning',
        })
      }
    }

    return result
  }, [
    filters.status,
    filters.type,
    filters.governorateId,
    filters.cityId,
    totalCount,
    desktopLoading,
    desktopCustomers,
    governorates,
  ])

  const columns = [
    {
      key: 'name',
      label: 'العميل',
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
    {
      key: 'type',
      label: 'النوع',
      hideOnMobile: true,
      render: (c: Customer) => (
        <Badge variant={typeBadge[c.type] || 'neutral'}>{typeLabels[c.type] || c.type}</Badge>
      ),
    },
    {
      key: 'location',
      label: 'الموقع',
      hideOnMobile: true,
      render: (c: Customer) => (
        <>
          <div style={{ fontSize: 'var(--text-sm)' }}>{(c as any).governorate?.name || '—'}</div>
          {(c as any).city && (
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
              {(c as any).city.name}
            </div>
          )}
        </>
      ),
    },
    {
      key: 'rep',
      label: 'المندوب',
      hideOnMobile: true,
      render: (c: Customer) => (c as any).assigned_rep?.full_name || (
        <span style={{ color: 'var(--text-muted)' }}>—</span>
      ),
    },
    {
      key: 'payment',
      label: 'الدفع',
      hideOnMobile: true,
      render: (c: Customer) => (
        <Badge variant={paymentBadge[c.payment_terms as string] || 'neutral'}>
          {paymentLabels[c.payment_terms as string] || c.payment_terms}
        </Badge>
      ),
    },
    {
      key: 'credit',
      label: 'الائتمان المتاح',
      hideOnMobile: true,
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
    {
      key: 'status',
      label: 'الحالة',
      render: (c: Customer) => (
        <Badge variant={c.is_active ? 'success' : 'danger'}>{c.is_active ? 'نشط' : 'معطل'}</Badge>
      ),
    },
    {
      key: 'actions',
      label: 'إجراءات',
      width: 100,
      render: (c: Customer) => (
        <div className="flex gap-1" onClick={e => e.stopPropagation()}>
          <Button
            variant="ghost"
            size="sm"
            title="عرض/تعديل"
            onClick={() => navigate(`/customers/${c.id}`)}
          >
            <Eye size={14} />
          </Button>
          {can('customers.update') && (
            <Button
              variant={c.is_active ? 'danger' : 'success'}
              size="sm"
              title={c.is_active ? 'تعطيل' : 'تفعيل'}
              onClick={() => handleToggle(c)}
            >
              {c.is_active ? <ToggleLeft size={14} /> : <ToggleRight size={14} />}
            </Button>
          )}
        </div>
      ),
    },
  ]

  const renderPagedTable = (items: Customer[]) => (
    <Card padding="none" className="customers-v2__table-card">
      <DataTable<Customer>
        columns={columns}
        data={items}
        loading={false}
        onRowClick={c => navigate(`/customers/${c.id}`)}
        rowStyle={c => ({ opacity: c.is_active ? 1 : 0.6 })}
        emptyIcon={<Users size={48} />}
        emptyTitle="لا يوجد عملاء"
        emptyText="لم يتم العثور على عملاء مطابقين للبحث"
        page={desktopPage}
        totalPages={totalPages}
        totalCount={totalCount}
        onPageChange={setDesktopPage}
      />
    </Card>
  )

  const renderMobileCards = (items: Customer[]) => (
    <div className="customers-v2__mobile-list">
      {items.map(c => (
        <DataCard
          key={c.id}
          title={c.name}
          subtitle={
            <span className="customers-v2__mobile-subtitle">
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
          badge={
            <Badge variant={c.is_active ? 'success' : 'danger'}>
              {c.is_active ? 'نشط' : 'معطل'}
            </Badge>
          }
          metadata={[
            { label: 'نوع العميل', value: typeLabels[c.type] || c.type },
            { label: 'طريقة الدفع', value: paymentLabels[c.payment_terms as string] || c.payment_terms },
            ...((c as any).governorate?.name
              ? [{ label: 'المحافظة', value: (c as any).governorate.name }]
              : []),
            ...((c as any).assigned_rep?.full_name
              ? [{ label: 'المندوب', value: (c as any).assigned_rep.full_name }]
              : []),
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
            <div className="customers-v2__mobile-actions">
              {((c.latitude && c.longitude) || (c.mobile || c.phone)) && (
                <div className="customers-v2__mobile-action-row">
                  {c.latitude && c.longitude && (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={e => {
                        e.stopPropagation()
                        window.open(
                          `https://www.google.com/maps/search/?api=1&query=${c.latitude},${c.longitude}`,
                          '_blank'
                        )
                      }}
                    >
                      <MapPin size={14} /> موقع
                    </Button>
                  )}
                  {(c.mobile || c.phone) && (
                    <Button
                      variant="secondary"
                      size="sm"
                      onClick={e => {
                        e.stopPropagation()
                        window.location.href = `tel:${c.mobile || c.phone}`
                      }}
                    >
                      <PhoneCall size={14} /> اتصال
                    </Button>
                  )}
                </div>
              )}
              {can('customers.update') && (
                <div className="customers-v2__mobile-action-row">
                  <Button
                    variant={c.is_active ? 'danger' : 'success'}
                    size="sm"
                    onClick={e => {
                      e.stopPropagation()
                      handleToggle(c)
                    }}
                  >
                    {c.is_active
                      ? <><ToggleLeft size={14} /> تعطيل</>
                      : <><ToggleRight size={14} /> تفعيل</>}
                  </Button>
                </div>
              )}
            </div>
          }
          onClick={() => navigate(`/customers/${c.id}`)}
        />
      ))}

      <div ref={sentinelRef} className="customers-v2__sentinel" />

      {mobileLoading && items.length > 0 && (
        <div className="customers-v2__infinite-loading">
          <Loader2 size={18} />
          <span>جاري تحميل المزيد...</span>
        </div>
      )}

      {!mobileLoading && !hasMoreMobile && items.length > 0 && (
        <div className="customers-v2__infinite-end">
          <CheckCircle2 size={16} />
          <span>جميع العملاء ({items.length.toLocaleString('en-US')})</span>
        </div>
      )}
    </div>
  )

  const collectionItems = device === 'mobile' ? mobileCustomers : desktopCustomers
  const collectionLoading = device === 'mobile'
    ? mobileLoading && mobileCustomers.length === 0
    : desktopLoading

  const collectionLoadingState = device === 'mobile' ? (
    <div className="customers-v2__loading-list" aria-label="جاري تحميل العملاء">
      {[1, 2, 3, 4].map(i => (
        <Card key={i} padding="md" className="customers-v2__loading-card">
          <div className="skeleton" style={{ height: 16, width: '60%' }} />
          <div className="skeleton" style={{ height: 12, width: '40%' }} />
          <div className="skeleton" style={{ height: 12, width: '80%' }} />
        </Card>
      ))}
    </div>
  ) : (
    <Card padding="md" aria-label="جاري تحميل العملاء">
      {[1, 2, 3, 4, 5].map(i => (
        <div key={i} className="skeleton skeleton-row" />
      ))}
    </Card>
  )

  const collectionEmptyState = (
    <StatePanel
      kind="empty"
      icon={<Users size={36} />}
      title="لا يوجد عملاء"
      description="لم يتم العثور على عملاء مطابقين للبحث"
      action={device !== 'mobile' && can('customers.create') ? (
        <Button icon={<Plus size={16} />} onClick={() => navigate('/customers/new')}>
          إضافة أول عميل
        </Button>
      ) : undefined}
    />
  )

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="العملاء"
        subtitle={desktopLoading ? '...' : `${totalCount.toLocaleString('en-US')} عميل`}
        actions={can('customers.create') ? (
          <Button
            icon={<Plus size={16} />}
            onClick={() => navigate('/customers/new')}
            className="desktop-only-btn"
          >
            إضافة عميل
          </Button>
        ) : undefined}
      />

      <FilterBar
        title="فلاتر العملاء"
        activeCount={activeCount}
        onReset={reset}
        stats={filterStats}
      >
        <FilterBar.Search
          value={filters.search}
          onChange={v => setFilter('search', v)}
          placeholder="بحث بالاسم أو الكود أو الهاتف..."
          fullWidth
        />

        <FilterBar.Select
          label="نوع العميل"
          value={filters.type}
          onChange={v => setFilter('type', v)}
          options={TYPE_OPTIONS}
          allLabel="كل الأنواع"
        />

        <FilterBar.Select
          label="المحافظة"
          value={filters.governorateId}
          onChange={handleGovChange}
          options={govOptions}
          allLabel="كل المحافظات"
        />

        {filters.governorateId && cityOptions.length > 0 && (
          <FilterBar.Select
            label="المدينة"
            value={filters.cityId}
            onChange={v => setFilter('cityId', v)}
            options={cityOptions}
            allLabel="كل المدن"
          />
        )}

        <FilterBar.Select
          label="المندوب"
          value={filters.repId}
          onChange={v => setFilter('repId', v)}
          options={repOptions}
          allLabel="كل المناديب"
        />

        <FilterBar.Select
          label="الحالة"
          value={filters.status}
          onChange={v => setFilter('status', v)}
          options={STATUS_OPTIONS}
          allLabel="نشط (افتراضي)"
        />
      </FilterBar>

      <ResponsiveCollection<Customer>
        items={collectionItems}
        loading={collectionLoading}
        loadingState={collectionLoadingState}
        emptyState={collectionEmptyState}
        renderDesktop={renderPagedTable}
        renderTablet={renderPagedTable}
        renderMobile={renderMobileCards}
      />

      <ResponsiveModal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title={confirmTarget?.is_active ? 'تعطيل العميل' : 'تفعيل العميل'}
        disableOverlayClose={toggling}
        footer={
          <>
            <Button
              variant="secondary"
              onClick={() => setConfirmTarget(null)}
              disabled={toggling}
            >
              إلغاء
            </Button>
            <Button
              variant={confirmTarget?.is_active ? 'danger' : 'success'}
              onClick={executeToggle}
              disabled={toggling}
            >
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
    </div>
  )
}
