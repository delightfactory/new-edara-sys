import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, Package, Tag, Barcode, Hash, DollarSign, Percent,
  Layers, Box, ShoppingBag, Truck as TruckIcon, AlertTriangle, FileText
} from 'lucide-react'
import { getProduct, getProductUnits } from '@/lib/services/products'
import { useAuthStore } from '@/stores/auth-store'
import type { Product, ProductUnit } from '@/lib/types/master-data'

export default function ProductDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [product, setProduct] = useState<Product | null>(null)
  const [units, setUnits] = useState<ProductUnit[]>([])

  useEffect(() => {
    if (!id) return
    const load = async () => {
      try {
        const [p, u] = await Promise.all([
          getProduct(id),
          getProductUnits(id),
        ])
        setProduct(p)
        setUnits(u)
      } catch { toast.error('فشل تحميل بيانات المنتج') }
      finally { setLoading(false) }
    }
    load()
  }, [id])

  if (loading) return (
    <div className="page-container animate-enter">
      {[1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) 0' }} />)}
    </div>
  )

  if (!product) return (
    <div className="page-container animate-enter">
      <div className="empty-state">
        <Package size={48} className="empty-state-icon" />
        <p className="empty-state-title">المنتج غير موجود</p>
        <button className="btn btn-primary" onClick={() => navigate('/products')}>العودة للمنتجات</button>
      </div>
    </div>
  )

  const InfoItem = ({ icon: Icon, label, value, dir, highlight }: { icon: any; label: string; value: string | number | null | undefined; dir?: string; highlight?: boolean }) => (
    <div style={{ display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)', padding: 'var(--space-3) 0', borderBottom: '1px solid var(--border-secondary)' }}>
      <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon size={14} style={{ color: 'var(--color-primary)' }} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>{label}</div>
        <div style={{
          fontSize: highlight ? 'var(--text-base)' : 'var(--text-sm)',
          fontWeight: highlight ? 700 : 500,
          color: value ? 'var(--text-primary)' : 'var(--text-muted)',
        }} dir={dir}>{value || '—'}</div>
      </div>
    </div>
  )

  const canViewCosts = can('finance.view_costs')

  const margin = canViewCosts && product.selling_price > 0 && product.cost_price > 0
    ? ((product.selling_price - product.cost_price) / product.selling_price * 100).toFixed(1)
    : null

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/products')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للمنتجات
          </button>
          <h1 className="page-title">{product.name}</h1>
          <p className="page-subtitle" dir="ltr" style={{ fontFamily: 'monospace' }}>{product.sku}</p>
        </div>
        <div className="page-actions">
          {can('products.update') && (
            <button className="btn btn-primary" onClick={() => navigate(`/products/${id}/edit`)}>
              <Edit size={16} /> تعديل
            </button>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        <div className="stat-card">
          <div className="stat-card-label">سعر البيع</div>
          <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)', color: 'var(--color-primary)' }}>
            {product.selling_price.toLocaleString('ar-EG')}
          </div>
        </div>
        {canViewCosts && (
          <div className="stat-card">
            <div className="stat-card-label">سعر التكلفة</div>
            <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)' }}>
              {product.cost_price.toLocaleString('ar-EG')}
            </div>
          </div>
        )}
        {canViewCosts && margin && (
          <div className="stat-card">
            <div className="stat-card-label">هامش الربح</div>
            <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)', color: 'var(--color-success)' }}>
              %{margin}
            </div>
          </div>
        )}
        <div className="stat-card">
          <div className="stat-card-label">التصنيف</div>
          <span className="badge badge-info" style={{ alignSelf: 'flex-start' }}>
            {product.category?.name || 'بدون'}
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الحالة</div>
          <span className={`badge ${product.is_active ? 'badge-success' : 'badge-danger'}`} style={{ alignSelf: 'flex-start' }}>
            {product.is_active ? 'نشط' : 'معطل'}
          </span>
        </div>
      </div>

      {/* Content */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 'var(--space-4)' }}>
        {/* Product Info */}
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            <Package size={16} style={{ color: 'var(--color-primary)' }} /> معلومات المنتج
          </h3>
          <InfoItem icon={Hash} label="كود المنتج (SKU)" value={product.sku} dir="ltr" />
          <InfoItem icon={Barcode} label="الباركود" value={product.barcode} dir="ltr" />
          <InfoItem icon={Tag} label="التصنيف" value={product.category?.name} />
          <InfoItem icon={Tag} label="العلامة التجارية" value={product.brand?.name} />
          <InfoItem icon={Box} label="الوحدة الأساسية" value={product.base_unit?.name} />
          <InfoItem icon={AlertTriangle} label="الحد الأدنى للمخزون" value={product.min_stock_level > 0 ? product.min_stock_level.toString() : '—'} />
        </div>

        {/* Pricing */}
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            <DollarSign size={16} style={{ color: 'var(--color-primary)' }} /> الأسعار
          </h3>
          <InfoItem icon={DollarSign} label="سعر البيع" value={product.selling_price.toLocaleString('ar-EG', { minimumFractionDigits: 2 })} highlight />
          {canViewCosts && <InfoItem icon={DollarSign} label="سعر التكلفة" value={product.cost_price.toLocaleString('ar-EG', { minimumFractionDigits: 2 })} />}
          <InfoItem icon={Percent} label="نسبة الضريبة" value={product.tax_rate > 0 ? `%${product.tax_rate}` : 'معفى'} />
          {canViewCosts && margin && <InfoItem icon={Percent} label="هامش الربح" value={`%${margin}`} />}
        </div>

        {/* Units */}
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            <Layers size={16} style={{ color: 'var(--color-primary)' }} /> وحدات القياس
          </h3>

          {/* Base unit */}
          <div style={{
            background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)',
            padding: 'var(--space-3)', border: '1px solid var(--border-primary)',
            marginBottom: 'var(--space-3)',
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
              <div>
                <span className="badge badge-primary" style={{ marginBottom: 4 }}>الوحدة الأساسية</span>
                <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{product.base_unit?.name}</div>
              </div>
              <div style={{ textAlign: 'left', fontSize: 'var(--text-sm)', fontWeight: 600 }}>
                {product.selling_price.toLocaleString('ar-EG')}
              </div>
            </div>
          </div>

          {/* Additional units */}
          {units.length === 0 ? (
            <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', textAlign: 'center', padding: 'var(--space-3)' }}>لا يوجد وحدات إضافية</p>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-2)' }}>
              {units.map(u => (
                <div key={u.id} style={{
                  background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)',
                  padding: 'var(--space-3)', border: '1px solid var(--border-secondary)',
                }}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 'var(--space-1)' }}>
                    <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{u.unit?.name}</div>
                    <div style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-primary)' }}>
                      {(u.selling_price ?? product.selling_price * u.conversion_factor).toLocaleString('ar-EG')}
                    </div>
                  </div>
                  <div style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    <span>= {u.conversion_factor} {product.base_unit?.name}</span>
                    {u.is_sales_unit && <span className="badge badge-success" style={{ fontSize: '0.6rem' }}><ShoppingBag size={8} /> بيع</span>}
                    {u.is_purchase_unit && <span className="badge badge-info" style={{ fontSize: '0.6rem' }}><TruckIcon size={8} /> شراء</span>}
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Description */}
        {product.description && (
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <FileText size={16} style={{ color: 'var(--color-primary)' }} /> الوصف
            </h3>
            <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7, whiteSpace: 'pre-wrap' }}>{product.description}</p>
          </div>
        )}
      </div>
    </div>
  )
}
