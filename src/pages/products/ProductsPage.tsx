import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { Plus, BoxesIcon, ToggleLeft, ToggleRight, Edit } from 'lucide-react'
import { getProducts, toggleProductActive } from '@/lib/services/products'
import { getCategories, getBrands } from '@/lib/services/products'
import { useAuthStore } from '@/stores/auth-store'
import type { Product, ProductCategory, Brand } from '@/lib/types/master-data'
import { formatCurrency } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import SearchInput from '@/components/shared/SearchInput'
import DataTable from '@/components/shared/DataTable'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

export default function ProductsPage() {
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const [products, setProducts] = useState<Product[]>([])
  const [categories, setCategories] = useState<ProductCategory[]>([])
  const [brands, setBrands] = useState<Brand[]>([])
  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState('')
  const [categoryFilter, setCategoryFilter] = useState('')
  const [brandFilter, setBrandFilter] = useState('')
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [totalPages, setTotalPages] = useState(1)
  const [totalCount, setTotalCount] = useState(0)
  // ConfirmDialog state
  const [confirmTarget, setConfirmTarget] = useState<Product | null>(null)

  const loadData = async () => {
    setLoading(true)
    try {
      const [res, cats, brds] = await Promise.all([
        getProducts({
          search, categoryId: categoryFilter, brandId: brandFilter,
          isActive: statusFilter === '' ? undefined : statusFilter === 'active',
          page, pageSize: 25,
        }),
        categories.length ? Promise.resolve(categories) : getCategories(),
        brands.length ? Promise.resolve(brands) : getBrands(),
      ])
      setProducts(res.data)
      setTotalPages(res.totalPages)
      setTotalCount(res.count)
      if (!categories.length) setCategories(cats as ProductCategory[])
      if (!brands.length) setBrands(brds as Brand[])
    } catch { toast.error('فشل تحميل المنتجات') }
    finally { setLoading(false) }
  }

  useEffect(() => { loadData() }, [search, categoryFilter, brandFilter, statusFilter, page])

  const handleToggle = async (p: Product) => {
    setConfirmTarget(p)
  }

  const executeToggle = async () => {
    if (!confirmTarget) return
    const next = !confirmTarget.is_active
    try {
      await toggleProductActive(confirmTarget.id, next)
      toast.success(`تم ${next ? 'تفعيل' : 'تعطيل'} المنتج`)
      loadData()
    } catch { toast.error('فشلت العملية') }
    finally { setConfirmTarget(null) }
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="المنتجات"
        subtitle={loading ? '...' : `${totalCount} منتج`}
        actions={can('products.create') ? (
          <Button icon={<Plus size={16} />} onClick={() => navigate('/products/new')}>
            إضافة منتج
          </Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <div style={{ flex: 1, minWidth: 200 }}>
            <SearchInput
              value={search}
              onChange={val => { setSearch(val); setPage(1) }}
              placeholder="بحث بالاسم أو الكود أو الباركود..."
            />
          </div>
          <select className="form-select" style={{ width: 160 }} value={categoryFilter}
            onChange={e => { setCategoryFilter(e.target.value); setPage(1) }}>
            <option value="">كل التصنيفات</option>
            {categories.map(c => <option key={c.id} value={c.id}>{c.name}</option>)}
          </select>
          <select className="form-select" style={{ width: 150 }} value={brandFilter}
            onChange={e => { setBrandFilter(e.target.value); setPage(1) }}>
            <option value="">كل العلامات</option>
            {brands.map(b => <option key={b.id} value={b.id}>{b.name}</option>)}
          </select>
          <select className="form-select" style={{ width: 120 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">الكل</option>
            <option value="active">نشط</option>
            <option value="inactive">معطل</option>
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
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
            ...(can('finance.view_costs') ? [{ key: 'cost_price' as const, label: 'التكلفة', hideOnMobile: true, render: (p: Product) => <span style={{ color: 'var(--text-secondary)' }}>{formatCurrency(p.cost_price)}</span> }] : []),
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
                    <Button
                      variant={p.is_active ? 'danger' : 'success'} size="sm"
                      title={p.is_active ? 'تعطيل' : 'تفعيل'}
                      onClick={() => handleToggle(p)}
                    >
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

      {/* Confirm Toggle Dialog */}
      <ConfirmDialog
        open={!!confirmTarget}
        title={confirmTarget?.is_active ? 'تعطيل المنتج' : 'تفعيل المنتج'}
        message={`هل تريد ${confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'} المنتج "${confirmTarget?.name}"؟`}
        variant={confirmTarget?.is_active ? 'danger' : 'info'}
        confirmText={confirmTarget?.is_active ? 'تعطيل' : 'تفعيل'}
        onConfirm={executeToggle}
        onCancel={() => setConfirmTarget(null)}
      />
    </div>
  )
}
