import { useState, useMemo, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, BoxesIcon, ToggleLeft, ToggleRight, Edit, Tag, DollarSign } from 'lucide-react'
import { toggleProductActive } from '@/lib/services/products'
import { useProducts, useCategories, useBrands, useInvalidate } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import type { Product, ProductCostMetrics } from '@/lib/types/master-data'
import { formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import DataCard from '@/components/ui/DataCard'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'

export default function ProductsPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()
  const [search, setSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [brandFilter, setBrandFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [confirmTarget, setConfirmTarget] = useState<Product | null>(null)
  const [toggling, setToggling] = useState(false)

  const { data: categories = [] } = useCategories()
  const { data: brands = [] } = useBrands()

  const queryParams = useMemo(() => ({
    search, categoryId: categoryFilter, brandId: brandFilter,
    isActive: statusFilter === '' ? undefined : statusFilter === 'active',
    page, pageSize: 25,
  }), [search, categoryFilter, brandFilter, statusFilter, page])

  const { data: result, isLoading: loading } = useProducts(queryParams)
  const products = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  const [metrics, setMetrics] = useState<Record<string, ProductCostMetrics>>({})
  useEffect(() => {
    if (products.length > 0 && can('finance.view_costs')) {
      const productIds = products.map(p => p.id)
      import('@/lib/services/products').then(s => s.getProductCostMetrics(productIds))
        .then(res => setMetrics(res))
        .catch(() => {}) // silently fail if not authorized
    }
  }, [products, can])

  const handleToggle = (p: Product) => setConfirmTarget(p)
  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    setToggling(true)
    try {
      await toggleProductActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'تعطيل'} المنتج`)
      invalidate('products')
    } catch { toast.error('فشلت العملية') }
    finally { setToggling(false); setConfirmTarget(null) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="المنتجات"
        subtitle={loading ? '...' : `${totalCount} منتج`}
        actions={can('products.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/products/new')}
            className="desktop-only-btn">
            إضافة منتج
          </Button>
        ) : undefined}
      />

      {/* ── Filters ─────────────────────────────────────────── */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="products-filter-row">
          <div style={{ flex: 2, minWidth: 180 }}>
            <SearchInput value={search} onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالاسم أو الكود أو الباركود..." />
          </div>
          <select className="form-select filter-select" value={categoryFilter}
            onChange={e => { setCategoryFilter(e.target.value); setPage(1) }}>
            <option value="">كل التصنيفات</option>
            {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <select className="form-select filter-select" value={brandFilter}
            onChange={e => { setBrandFilter(e.target.value); setPage(1) }}>
            <option value="">كل العلامات</option>
            {brands.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
          <select className="form-select filter-select" value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">الحالة</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>

      {/* ── DESKTOP: Data Table ──────────────────────────────── */}
      <div className="products-table-view edara-card" style={{ overflow: 'auto' }}>
        <DataTable<Product>
          columns={[
            {
              key: 'name', label: 'المنتج',
              render: p => (
                <>
                  <div style={{ fontWeight: 600 }}>{p.name}</div>
                  {p.barcode && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }} dir="ltr">{p.barcode}</div>}
                </>
              ),
            },
            { key: 'sku', label: 'الكود', hideOnMobile: true, render: p => <span dir="ltr" style={{ color: 'var(--text-secondary)', fontFamily: 'monospace' }}>{p.sku}</span> },
            { key: 'category', label: 'التصنيف', hideOnMobile: true, render: p => p.category?.name || '—' },
            { key: 'brand', label: 'العلامة', hideOnMobile: true, render: p => p.brand?.name || '—' },
            { key: 'selling_price', label: 'سعر البيع', render: p => <span style={{ fontWeight: 600 }}>{formatCurrency(p.selling_price)}</span> },
            ...(can('finance.view_costs') ? [{ key: 'cost_price' as const, label: 'التكلفة', hideOnMobile: true, render: (p: Product) => <span style={{ color: 'var(--text-secondary)' }}>{formatCurrency(metrics[p.id]?.global_wac ?? metrics[p.id]?.cost_price ?? p.cost_price ?? 0)}</span> }] : []),
            { key: 'is_active', label: 'الحالة', render: p => <Badge variant={p.is_active ? 'success' : 'danger'}>{p.is_active ? 'نشط' : 'معطل'}</Badge> },
            {
              key: 'actions', label: 'إجراءات', width: 120,
              render: p => (
                <div className="flex gap-1" onClick={e => e.stopPropagation()}>
                  {can('products.update') && (
                    <Button variant="ghost" size="sm" title="تعديل" onClick={() => navigate(`/products/${p.id}/edit`)}>
                      <Edit size={14} />
                    </Button>
                  )}
                  {can('products.update') && (
                    <Button variant={p.is_active ? 'danger' : 'success'} size="sm"
                      title={p.is_active ? 'تعطيل' : 'تفعيل'}
                      onClick={() => handleToggle(p)}>
                      {p.is_active ? <ToggleLeft size={14} /> : <ToggleRight size={14} />}
                    </Button>
                  )}
                </div>
              ),
            },
          ]}
          data={products}
          loading={loading}
          onRowClick={p => navigate(`/products/${p.id}`)}
          rowStyle={p => ({ opacity: p.is_active ? 1 : 0.6 })}
          emptyIcon={<BoxesIcon size={48} />}
          emptyTitle="لا يوجد منتجات"
          emptyText="لم يتم العثور على منتجات مطابقة للبحث"
          emptyAction={can('products.create') ? (
            <Button icon={<Plus size={16} />} onClick={() => navigate('/products/new')}>إضافة أول منتج</Button>
          ) : undefined}
          page={page}
          totalPages={totalPages}
          totalCount={totalCount}
          onPageChange={setPage}
        />
      </div>

      {/* ── MOBILE: DataCard list ────────────────────────────── */}
      <div className="products-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1, 2, 3, 4].map(i => (
              <div key={i} className="edara-card" style={{ padding: 'var(--space-4)' }}>
                <div className="skeleton" style={{ height: 16, width: '55%', marginBottom: 8 }} />
                <div className="skeleton" style={{ height: 12, width: '35%', marginBottom: 12 }} />
                <div className="skeleton" style={{ height: 12, width: '75%' }} />
              </div>
            ))}
          </div>
        ) : products.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <BoxesIcon size={40} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد منتجات</p>
            <p className="empty-state-text">لم يتم العثور على منتجات مطابقة للبحث</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {products.map(p => (
              <DataCard
                key={p.id}
                title={p.name}
                subtitle={
                  <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: '0.7rem', color: 'var(--text-muted)' }}>
                    {p.sku}
                  </span>
                }
                badge={<Badge variant={p.is_active ? 'success' : 'danger'}>{p.is_active ? 'نشط' : 'معطل'}</Badge>}
                leading={
                  <div style={{
                    width: 40, height: 40, borderRadius: 'var(--radius-md)',
                    background: 'var(--bg-accent)', display: 'flex', alignItems: 'center', justifyContent: 'center'
                  }}>
                    <Tag size={18} style={{ color: 'var(--color-primary)' }} />
                  </div>
                }
                metadata={[
                  { label: 'سعر البيع', value: formatCurrency(p.selling_price), highlight: true },
                  ...(p.category?.name ? [{ label: 'التصنيف', value: p.category.name }] : []),
                  ...(p.brand?.name ? [{ label: 'العلامة', value: p.brand.name }] : []),
                  ...(can('finance.view_costs') ? [{ label: 'التكلفة', value: formatCurrency(metrics[p.id]?.global_wac ?? metrics[p.id]?.cost_price ?? p.cost_price ?? 0) }] : []),
                ]}
                actions={
                  <div className="flex gap-2" style={{ width: '100%' }}>
                    {can('products.update') && (
                      <Button variant="secondary" size="sm" onClick={() => navigate(`/products/${p.id}/edit`)}
                        style={{ flex: 1, justifyContent: 'center' }}>
                        <Edit size={14} /> تعديل
                      </Button>
                    )}
                    {can('products.update') && (
                      <Button variant={p.is_active ? 'danger' : 'success'} size="sm"
                        onClick={() => handleToggle(p)}
                        style={{ flex: 1, justifyContent: 'center' }}>
                        {p.is_active ? <><ToggleLeft size={14} /> تعطيل</> : <><ToggleRight size={14} /> تفعيل</>}
                      </Button>
                    )}
                  </div>
                }
                onClick={() => navigate(`/products/${p.id}`)}
              />
            ))}
          </div>
        )}

        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>
              {page} / {totalPages}
            </span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      {/* ── Responsive Confirm Modal ─────────────────────────── */}
      <ResponsiveModal
        open={!!confirmTarget}
        onClose={() => setConfirmTarget(null)}
        title={confirmTarget?.is_active ? 'تعطيل المنتج' : 'تفعيل المنتج'}
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
          هل تريد {confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} المنتج{' '}
          <strong style={{ color: 'var(--text-primary)' }}>"{confirmTarget?.name}"</strong>؟
        </p>
      </ResponsiveModal>

      <style>{`
        .products-filter-row {
          display: flex;
          gap: var(--space-3);
          flex-wrap: wrap;
          align-items: flex-end;
        }
        .filter-select { min-width: 100px; flex: 1; }

        .products-table-view { display: block; }
        .products-card-view  { display: none; }

        @media (max-width: 768px) {
          .products-table-view { display: none; }
          .products-card-view  { display: block; }
          .desktop-only-btn    { display: none; }
          .filter-select { font-size: var(--text-xs); }
        }

        .mobile-card-list {
          display: flex;
          flex-direction: column;
          gap: var(--space-3);
          padding: 0 0 var(--space-2);
        }
        .mobile-pagination {
          display: flex;
          align-items: center;
          justify-content: center;
          gap: var(--space-4);
          padding: var(--space-4) 0;
        }
      `}</style>
    </div>
  )
}
