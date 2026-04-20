import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, Package, Tag, Barcode, Hash, DollarSign, Percent,
  Layers, Box, ShoppingBag, Truck as TruckIcon, AlertTriangle, FileText,
  Warehouse as WarehouseIcon,
} from 'lucide-react'
import { getProduct, getProductUnits, getProductCostMetrics } from '@/lib/services/products'
import { useAuthStore } from '@/stores/auth-store'
import type { Product, ProductUnit, ProductCostMetrics } from '@/lib/types/master-data'

export default function ProductDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [product, setProduct] = useState<Product | null>(null)
  const [metrics, setMetrics] = useState<ProductCostMetrics | null>(null)
  const [units, setUnits] = useState<ProductUnit[]>([])
  const [tab, setTab] = useState<'info' | 'pricing' | 'units' | 'desc'>('info')

  useEffect(() => {
    if (!id) return
    const load = async () => {
      try {
        const [p, u] = await Promise.all([getProduct(id), getProductUnits(id)])
        setProduct(p)
        setUnits(u)
        
        if (can('finance.view_costs')) {
          getProductCostMetrics([id])
            .then(res => res[id] && setMetrics(res[id]))
            .catch(() => {})
        }
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

  const canViewCosts = can('finance.view_costs')
  const actualCost = metrics?.global_wac ?? metrics?.cost_price ?? product.cost_price ?? 0
  const margin = canViewCosts && product.selling_price > 0 && actualCost > 0
    ? ((product.selling_price - actualCost) / product.selling_price * 100).toFixed(1)
    : null

  // Build tab list dynamically
  const tabs: { key: typeof tab; label: string; icon: any }[] = [
    { key: 'info', label: 'المعلومات', icon: Package },
    { key: 'pricing', label: 'الأسعار', icon: DollarSign },
    { key: 'units', label: 'الوحدات', icon: Layers },
    ...(product.description ? [{ key: 'desc' as const, label: 'الوصف', icon: FileText }] : []),
  ]

  return (
    <div style={{ maxWidth: 900, margin: '0 auto', paddingBottom: 80 }}>

      {/* ══ Sticky Hero ══ */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 10,
        background: 'var(--bg-surface)',
        borderBottom: '2px solid var(--color-primary)',
        backdropFilter: 'blur(12px)',
        padding: '14px 16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <button onClick={() => navigate('/products')}
            style={{ background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)', borderRadius: 10, padding: '7px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0 }}>
            <ArrowRight size={14} /> رجوع
          </button>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 17, fontWeight: 800, margin: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', maxWidth: 260 }}>
                {product.name}
              </h1>
              <span className={`badge ${product.is_active ? 'badge-success' : 'badge-danger'}`}>
                {product.is_active ? 'نشط' : 'معطل'}
              </span>
              {product.category && (
                <span className="badge badge-info">{product.category.name}</span>
              )}
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2, fontFamily: 'monospace' }} dir="ltr">
              {product.sku}
              {product.barcode && <span style={{ marginRight: 10, opacity: 0.7 }}>| {product.barcode}</span>}
            </div>
          </div>
          {can('products.update') && (
            <button className="btn btn-primary btn-sm"
              onClick={() => navigate(`/products/${id}/edit`)}
              style={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 5 }}>
              <Edit size={14} /> تعديل
            </button>
          )}
        </div>

        {/* KPI pills */}
        <div style={{ display: 'flex', gap: 10, marginTop: 12, flexWrap: 'wrap' }}>
          <div style={{
            background: 'color-mix(in srgb, var(--color-primary) 10%, transparent)',
            border: '1px solid color-mix(in srgb, var(--color-primary) 25%, transparent)',
            borderRadius: 8, padding: '6px 12px', fontSize: 13,
          }}>
            <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>سعر البيع  </span>
            <span style={{ fontWeight: 700, color: 'var(--color-primary)' }}>
              {product.selling_price.toLocaleString('ar-EG-u-nu-latn')} ج.م
            </span>
          </div>
          {canViewCosts && actualCost != null && (
            <div style={{
              background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)',
              borderRadius: 8, padding: '6px 12px', fontSize: 13,
            }}>
              <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>التكلفة  </span>
              <span style={{ fontWeight: 700 }}>{actualCost.toLocaleString('ar-EG-u-nu-latn')}</span>
            </div>
          )}
          {margin && (
            <div style={{
              background: 'color-mix(in srgb, var(--color-success) 10%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-success) 25%, transparent)',
              borderRadius: 8, padding: '6px 12px', fontSize: 13,
            }}>
              <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>هامش  </span>
              <span style={{ fontWeight: 700, color: 'var(--color-success)' }}>%{margin}</span>
            </div>
          )}
          {product.min_stock_level > 0 && (
            <div style={{
              background: 'color-mix(in srgb, var(--color-warning) 10%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
              borderRadius: 8, padding: '6px 12px', fontSize: 13, display: 'flex', alignItems: 'center', gap: 5,
            }}>
              <AlertTriangle size={12} style={{ color: 'var(--color-warning)' }} />
              <span style={{ color: 'var(--text-muted)', fontSize: 11 }}>الحد الأدنى  </span>
              <span style={{ fontWeight: 700, color: 'var(--color-warning)' }}>{product.min_stock_level}</span>
            </div>
          )}
        </div>
      </div>

      {/* ══ Tabs — scrollable on mobile ══ */}
      <div className="tabs" style={{ overflowX: 'auto', scrollbarWidth: 'none', flexWrap: 'nowrap', padding: '0 12px', marginTop: 8 }}>
        {tabs.map(t => (
          <button key={t.key}
            className={`tab ${tab === t.key ? 'active' : ''}`}
            onClick={() => setTab(t.key)}
            style={{ flexShrink: 0, display: 'flex', alignItems: 'center', gap: 5 }}>
            <t.icon size={13} /> {t.label}
          </button>
        ))}
      </div>

      <div style={{ padding: '12px 12px 0' }}>

        {/* ══ TAB: Info ══ */}
        {tab === 'info' && (
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <InfoRow icon={Hash} label="كود المنتج (SKU)" value={product.sku} dir="ltr" />
            <InfoRow icon={Barcode} label="الباركود" value={product.barcode} dir="ltr" />
            <InfoRow icon={Tag} label="التصنيف" value={product.category?.name} />
            <InfoRow icon={Tag} label="العلامة التجارية" value={product.brand?.name} />
            <InfoRow icon={Box} label="الوحدة الأساسية" value={product.base_unit?.name} />
            {product.min_stock_level > 0 && (
              <InfoRow icon={AlertTriangle} label="الحد الأدنى للمخزون" value={String(product.min_stock_level)} />
            )}
          </div>
        )}

        {/* ══ TAB: Pricing ══ */}
        {tab === 'pricing' && (
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <InfoRow icon={DollarSign} label="سعر البيع" value={product.selling_price.toLocaleString('en-US', { minimumFractionDigits: 2 })} highlight />
            {canViewCosts && (
              <>
                <InfoRow icon={DollarSign} label="متوسط التكلفة العام (WAC)" value={
                  (metrics?.global_wac != null
                    ? metrics.global_wac
                    : (metrics?.cost_price ?? product.cost_price ?? 0)
                  ).toLocaleString('en-US', { minimumFractionDigits: 2 })
                } />
                <InfoRow icon={DollarSign} label="آخر سعر شراء" value={
                  (metrics?.last_purchase_price ?? product.last_purchase_price) != null
                    ? (metrics?.last_purchase_price ?? product.last_purchase_price ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2 })
                    : '—'
                } />
                <InfoRow icon={DollarSign} label="تكلفة مرجعية (Cost Price)" value={(metrics?.cost_price ?? product.cost_price ?? 0).toLocaleString('en-US', { minimumFractionDigits: 2 })} />
                
                {/* Warehouse breakdown */}
                {metrics && metrics.warehouse_breakdown && metrics.warehouse_breakdown.length > 0 && (
                  <div style={{ marginTop: 20, paddingTop: 16, borderTop: '1px solid var(--border-color)' }}>
                    <div style={{ fontWeight: 700, fontSize: 14, marginBottom: 12 }}>تفصيل المخزون والتكلفة :</div>
                    <div style={{ display: 'grid', gap: 10 }}>
                      {metrics.warehouse_breakdown.map((wb, i) => (
                        <div key={i} style={{ display: 'flex', justifyContent: 'space-between', padding: 12, background: 'var(--bg-surface-2)', borderRadius: 8, fontSize: 13 }}>
                          <span style={{ fontWeight: 600 }}>{wb.warehouse_name}</span>
                          <div style={{ display: 'flex', gap: 16, color: 'var(--text-secondary)' }}>
                            <span>الكمية: {wb.quantity}</span>
                            <span style={{ fontWeight: 600, color: 'var(--text-primary)' }}>التكلفة: {wb.wac.toLocaleString('en-US', { minimumFractionDigits: 2 })}</span>
                          </div>
                        </div>
                      ))}
                    </div>
                  </div>
                )}
              </>
            )}
            <InfoRow icon={Percent} label="نسبة الضريبة" value={product.tax_rate > 0 ? `%${product.tax_rate}` : 'معفى'} />
            {canViewCosts && margin && <InfoRow icon={Percent} label="هامش الربح" value={`%${margin}`} highlight />}
          </div>
        )}

        {/* ══ TAB: Units ══ */}
        {tab === 'units' && (
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            {/* Base unit */}
            <div style={{
              background: 'color-mix(in srgb, var(--color-primary) 8%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-primary) 25%, transparent)',
              borderRadius: 10, padding: 12, marginBottom: 12,
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            }}>
              <div>
                <span className="badge badge-primary" style={{ marginBottom: 4 }}>الوحدة الأساسية</span>
                <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>{product.base_unit?.name}</div>
              </div>
              <div style={{ fontWeight: 700, fontSize: 15, fontVariantNumeric: 'tabular-nums' }}>
                {product.selling_price.toLocaleString('ar-EG-u-nu-latn')}
              </div>
            </div>

            {/* Additional units */}
            {units.length === 0 ? (
              <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', textAlign: 'center', padding: 'var(--space-4 0)' }}>لا يوجد وحدات إضافية</p>
            ) : (
              <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
                {units.map(u => (
                  <div key={u.id} style={{
                    background: 'var(--bg-surface-2)', borderRadius: 10,
                    padding: 12, border: '1px solid var(--border-secondary)',
                    display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                  }}>
                    <div>
                      <div style={{ fontWeight: 600, fontSize: 14 }}>{u.unit?.name}</div>
                      <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 3, display: 'flex', gap: 6, flexWrap: 'wrap' }}>
                        <span>= {u.conversion_factor} {product.base_unit?.name}</span>
                        {u.is_sales_unit && <span className="badge badge-success" style={{ fontSize: '0.6rem' }}><ShoppingBag size={8} /> بيع</span>}
                        {u.is_purchase_unit && <span className="badge badge-info" style={{ fontSize: '0.6rem' }}><TruckIcon size={8} /> شراء</span>}
                      </div>
                    </div>
                    <div style={{ fontWeight: 700, fontSize: 15, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                      {(u.selling_price ?? product.selling_price * u.conversion_factor).toLocaleString('ar-EG-u-nu-latn')}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        )}

        {/* ══ TAB: Description ══ */}
        {tab === 'desc' && product.description && (
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 12 }}>
              <WarehouseIcon size={16} style={{ color: 'var(--color-primary)' }} />
              <span style={{ fontWeight: 700 }}>الوصف</span>
            </div>
            <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)', lineHeight: 1.7, whiteSpace: 'pre-wrap', margin: 0 }}>
              {product.description}
            </p>
          </div>
        )}

      </div>
    </div>
  )
}

/* ── helpers ── */
function InfoRow({ icon: Icon, label, value, dir, highlight }: {
  icon: any; label: string; value?: string | number | null; dir?: string; highlight?: boolean
}) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 12, padding: '10px 0', borderBottom: '1px solid var(--border-secondary)' }}>
      <div style={{ width: 30, height: 30, borderRadius: 8, background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0 }}>
        <Icon size={13} style={{ color: 'var(--color-primary)' }} />
      </div>
      <div style={{ flex: 1, minWidth: 0, display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
        <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{label}</span>
        <span style={{
          fontSize: highlight ? 'var(--text-base)' : 'var(--text-sm)',
          fontWeight: highlight ? 700 : 500,
          color: value ? 'var(--text-primary)' : 'var(--text-muted)',
          fontFamily: dir === 'ltr' ? 'monospace' : 'inherit',
          direction: dir as 'ltr' | 'rtl' | undefined,
          textAlign: 'left',
        }}>{value ?? '—'}</span>
      </div>
    </div>
  )
}
