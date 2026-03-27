import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, CheckCircle, XCircle, RotateCcw, FileText,
  User, Clock, Package, CreditCard, Banknote,
} from 'lucide-react'
import { useAuthStore } from '@/stores/auth-store'
import { useVaults, useCustodyAccounts, useInvalidate } from '@/hooks/useQueryHooks'
import { getSalesReturn, confirmSalesReturn } from '@/lib/services/sales'
import { formatNumber } from '@/lib/utils/format'
import type { SalesReturn, SalesReturnStatus } from '@/lib/types/master-data'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'

const statusLabels: Record<SalesReturnStatus, string> = {
  draft: 'مسودة', confirmed: 'مؤكد', cancelled: 'ملغي',
}
const statusVariants: Record<SalesReturnStatus, 'neutral' | 'success' | 'danger'> = {
  draft: 'neutral', confirmed: 'success', cancelled: 'danger',
}
const statusColors: Record<SalesReturnStatus, string> = {
  draft: '#6b7280', confirmed: '#16a34a', cancelled: '#dc2626',
}

export default function SalesReturnDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const invalidate = useInvalidate()

  const [ret, setRet] = useState<SalesReturn | null>(null)
  const [loading, setLoading] = useState(true)
  const [actionLoading, setActionLoading] = useState(false)

  // Confirm modal
  const [showConfirm, setShowConfirm] = useState(false)
  const [confirmVaultId, setConfirmVaultId] = useState('')
  const [confirmCustodyId, setConfirmCustodyId] = useState('')

  // Cancel modal
  const [showCancel, setShowCancel] = useState(false)

  const { data: vaults = [] } = useVaults({ isActive: true })
  const { data: custodyAccounts = [] } = useCustodyAccounts({ isActive: true })

  const loadReturn = async () => {
    if (!id) return
    try {
      setLoading(true)
      const data = await getSalesReturn(id)
      setRet(data)
    } catch {
      toast.error('فشل تحميل المرتجع')
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { loadReturn() }, [id])

  // Is cash return? (needs vault/custody)
  const isCashReturn = ret?.order?.payment_terms === 'cash' || ret?.order?.payment_terms === 'mixed'

  const handleConfirm = async () => {
    if (isCashReturn && !confirmVaultId && !confirmCustodyId) {
      toast.error('يجب تحديد خزينة أو عهدة لرد المبلغ النقدي')
      return
    }
    setActionLoading(true)
    try {
      await confirmSalesReturn(id!, {
        vaultId: confirmVaultId || null,
        custodyId: confirmCustodyId || null,
      })
      toast.success('تم تأكيد المرتجع وإعادة المخزون')
      setShowConfirm(false)
      invalidate('sales-returns', 'sales-orders', 'sales-stats', 'stock', 'vaults', 'custody-accounts')
      await loadReturn()
    } catch (e: any) {
      toast.error(e.message || 'فشل تأكيد المرتجع')
    } finally {
      setActionLoading(false)
    }
  }

  const handleCancel = async () => {
    setActionLoading(true)
    try {
      const { error } = await (await import('@/lib/supabase/client')).supabase
        .from('sales_returns')
        .update({ status: 'cancelled', cancelled_by: (await (await import('@/lib/supabase/client')).supabase.auth.getUser()).data.user?.id, cancelled_at: new Date().toISOString() })
        .eq('id', id!)
        .eq('status', 'draft')
      if (error) throw error
      toast.success('تم إلغاء المرتجع')
      setShowCancel(false)
      invalidate('sales-returns')
      await loadReturn()
    } catch (e: any) {
      toast.error(e.message || 'فشل الإلغاء')
    } finally {
      setActionLoading(false)
    }
  }

  if (loading || !ret) {
    return <div className="page-container animate-enter">
      <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center' }}>
        {loading ? 'جاري التحميل...' : 'المرتجع غير موجود'}
      </div>
    </div>
  }

  const sc = statusColors[ret.status]

  return (
    <div style={{ maxWidth: 800, margin: '0 auto', padding: '0 0 140px' }}>

      {/* ══ Sticky Hero Header ══ */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 10,
        background: `linear-gradient(135deg, ${sc}12, ${sc}06)`,
        borderBottom: `3px solid ${sc}30`,
        backdropFilter: 'blur(12px)',
        padding: '14px 16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <button onClick={() => navigate('/sales/returns')}
            style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 10, padding: '7px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0 }}>
            <ArrowRight size={14} /> رجوع
          </button>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 18, fontWeight: 800, margin: 0, whiteSpace: 'nowrap' }}>
                مرتجع #{ret.return_number}
              </h1>
              <span style={{
                fontSize: 11, fontWeight: 700, padding: '3px 10px', borderRadius: 99,
                background: ret.status === 'confirmed' ? 'var(--color-success-light, #f0fdf4)' : ret.status === 'cancelled' ? 'var(--color-danger-light, #fef2f2)' : 'var(--bg-secondary)',
                color: ret.status === 'confirmed' ? 'var(--color-success)' : ret.status === 'cancelled' ? 'var(--color-danger)' : 'var(--text-muted)',
              }}>
                {statusLabels[ret.status]}
              </span>
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
              {ret.customer?.name} • {formatNumber(ret.total_amount)} ج.م
            </div>
          </div>
          {/* Desktop action buttons — shown only on desktop */}
          <div className="rtn-desktop-actions">
            {ret.status === 'draft' && can('sales.returns.confirm') && (
              <Button icon={<CheckCircle size={16} />} onClick={() => setShowConfirm(true)} disabled={actionLoading}>
                تأكيد
              </Button>
            )}
            {ret.status === 'draft' && (
              <Button variant="danger" icon={<XCircle size={16} />} onClick={() => setShowCancel(true)} disabled={actionLoading}>
                إلغاء
              </Button>
            )}
          </div>
        </div>
      </div>

      {/* ══ Cards Grid ══ */}
      <div style={{ padding: '12px 12px 0' }}>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(300px, 1fr))', gap: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
          {/* Details */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <FileText size={18} /> بيانات المرتجع
            </h3>
            <div style={{ display: 'grid', gap: 'var(--space-3)' }}>
              <InfoRow icon={<RotateCcw size={14} />} label="رقم المرتجع" value={ret.return_number} />
              <InfoRow icon={<Clock size={14} />} label="التاريخ" value={new Date(ret.return_date).toLocaleDateString('ar-EG-u-nu-latn')} />
              <InfoRow icon={<User size={14} />} label="العميل" value={ret.customer?.name} />
              <InfoRow icon={<Package size={14} />} label="المخزن" value={ret.warehouse?.name || 'مخزن الفاتورة'} />
              <InfoRow icon={<FileText size={14} />} label="الفاتورة الأصلية"
                value={ret.order?.order_number}
                onClick={() => navigate(`/sales/orders/${ret.order_id}`)} />
              <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>الحالة</span>
                <Badge variant={statusVariants[ret.status]}>{statusLabels[ret.status]}</Badge>
              </div>
              {ret.reason && <InfoRow label="السبب" value={ret.reason} />}
              {ret.confirmed_by_profile && (
                <InfoRow icon={<User size={14} />} label="أكّده" value={ret.confirmed_by_profile.full_name} />
              )}
              {ret.confirmed_at && (
                <InfoRow icon={<Clock size={14} />} label="تاريخ التأكيد"
                  value={new Date(ret.confirmed_at).toLocaleDateString('ar-EG', { hour: '2-digit', minute: '2-digit' })} />
              )}
            </div>
          </div>

          {/* Financial */}
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-4)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <CreditCard size={18} /> الملخص المالي
            </h3>
            <div style={{ display: 'grid', gap: 'var(--space-3)' }}>
              <div style={{ borderBottom: '2px solid var(--border-color)', paddingBottom: 'var(--space-3)', display: 'flex', justifyContent: 'space-between' }}>
                <span style={{ fontWeight: 700, fontSize: 'var(--text-lg)' }}>إجمالي المرتجع</span>
                <span style={{ fontWeight: 700, fontSize: 'var(--text-lg)', color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
                  {formatNumber(ret.total_amount)} ج.م
                </span>
              </div>
              <InfoRow icon={<Banknote size={14} />} label="طريقة الدفع الأصلية"
                value={ret.order?.payment_terms === 'cash' ? 'نقدي' : ret.order?.payment_terms === 'credit' ? 'آجل' : 'مختلط'} />
              <InfoRow label="إجمالي الفاتورة الأصلية" value={`${formatNumber(ret.order?.total_amount || 0)} ج.م`} />
              {isCashReturn && ret.status === 'draft' && (
                <div style={{
                  padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
                  background: 'rgba(245, 158, 11, 0.08)', border: '1px solid rgba(245, 158, 11, 0.2)',
                  fontSize: 'var(--text-xs)', color: 'var(--color-warning)',
                }}>
                  ⚠️ مرتجع نقدي — يتطلب تحديد خزينة أو عهدة للرد عند التأكيد
                </div>
              )}
              {!isCashReturn && ret.status === 'draft' && (
                <div style={{
                  padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
                  background: 'rgba(59, 130, 246, 0.08)', border: '1px solid rgba(59, 130, 246, 0.2)',
                  fontSize: 'var(--text-xs)', color: 'var(--color-info)',
                }}>
                  ℹ️ مرتجع آجل — سيُخصم المبلغ من مديونية العميل تلقائياً
                </div>
              )}
            </div>
          </div>
        </div>
      </div>

      {/* ══ Items — desktop table / mobile cards ══ */}
      <div style={{ padding: '0 12px' }}>
        <div className="rtn-table-view edara-card" style={{ padding: 'var(--space-5)', overflow: 'auto' }}>
          <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-4)' }}>
            بنود المرتجع ({ret.items?.length || 0})
          </h3>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 'var(--text-sm)' }}>
            <thead>
              <tr style={{ borderBottom: '2px solid var(--border-color)', textAlign: 'right' }}>
                <th style={{ padding: 'var(--space-2)' }}>المنتج</th>
                <th style={{ padding: 'var(--space-2)' }}>الكمية</th>
                <th style={{ padding: 'var(--space-2)' }}>السعر</th>
                <th style={{ padding: 'var(--space-2)' }}>الإجمالي</th>
              </tr>
            </thead>
            <tbody>
              {(ret.items || []).map(item => (
                <tr key={item.id} style={{ borderBottom: '1px solid var(--border-color)' }}>
                  <td style={{ padding: 'var(--space-2)' }}>
                    <div style={{ fontWeight: 500 }}>{item.product?.name}</div>
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{item.product?.sku}</div>
                  </td>
                  <td style={{ padding: 'var(--space-2)', fontVariantNumeric: 'tabular-nums' }}>{item.quantity} {item.unit?.symbol || item.unit?.name || ''}</td>
                  <td style={{ padding: 'var(--space-2)', fontVariantNumeric: 'tabular-nums' }}>{formatNumber(item.unit_price)} ج.م</td>
                  <td style={{ padding: 'var(--space-2)', fontWeight: 600, fontVariantNumeric: 'tabular-nums' }}>{formatNumber(item.line_total)} ج.م</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>

        {/* Mobile item cards */}
        <div className="rtn-card-view">
          <div style={{ fontWeight: 700, fontSize: 13, padding: '0 4px 10px', color: 'var(--text-secondary)' }}>
            البنود ({ret.items?.length || 0})
          </div>
          {(ret.items || []).map(item => (
            <div key={item.id} style={{
              background: 'var(--bg-surface)', border: '1px solid var(--border-primary)',
              borderRadius: 10, padding: 12, marginBottom: 8,
              display: 'flex', justifyContent: 'space-between', alignItems: 'center',
            }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: 13 }}>{item.product?.name}</div>
                <div style={{ fontSize: 11, color: 'var(--text-muted)', fontFamily: 'monospace', marginTop: 2 }}>{item.product?.sku}</div>
                <div style={{ fontSize: 12, color: 'var(--text-secondary)', marginTop: 4 }}>
                  {item.quantity} {item.unit?.symbol || item.unit?.name || ''} × {formatNumber(item.unit_price)} ج.م
                </div>
              </div>
              <div style={{ fontWeight: 800, fontSize: 14, color: 'var(--color-danger)', fontVariantNumeric: 'tabular-nums', flexShrink: 0 }}>
                {formatNumber(item.line_total)} ج.م
              </div>
            </div>
          ))}
        </div>
      </div>

      {/* Notes */}
      {ret.notes && (
        <div style={{ padding: '12px 12px 0' }}>
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 600, marginBottom: 'var(--space-3)' }}>ملاحظات</h3>
            <p style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>{ret.notes}</p>
          </div>
        </div>
      )}

      {/* ══ Sticky Mobile Action Bar — only on draft status ══ */}
      {ret.status === 'draft' && (
        <div className="rtn-action-bar">
          {can('sales.returns.confirm') && (
            <button type="button" className="btn btn-primary"
              style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}
              onClick={() => setShowConfirm(true)} disabled={actionLoading}>
              <CheckCircle size={16} /> تأكيد المرتجع
            </button>
          )}
          <button type="button" className="btn btn-danger"
            style={{ flex: can('sales.returns.confirm') ? '0 0 auto' : 1, paddingInline: 20, display: 'flex', alignItems: 'center', gap: 6 }}
            onClick={() => setShowCancel(true)} disabled={actionLoading}>
            <XCircle size={16} /> إلغاء
          </button>
        </div>
      )}

      {/* ═══════ Confirm Modal (ResponsiveModal = bottom-sheet on mobile) ═══════ */}
      <ResponsiveModal open={showConfirm} onClose={() => setShowConfirm(false)} title="تأكيد المرتجع">
        <div style={{ display: 'grid', gap: 'var(--space-4)' }}>
          <div style={{
            padding: 'var(--space-4)', borderRadius: 'var(--radius-md)', textAlign: 'center',
            background: 'rgba(var(--color-primary-rgb, 59,130,246), 0.06)',
            border: '1px solid rgba(var(--color-primary-rgb, 59,130,246), 0.15)',
          }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المبلغ المرتجع</div>
            <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: 'var(--color-primary)', fontVariantNumeric: 'tabular-nums' }}>
              {formatNumber(ret.total_amount)} ج.م
            </div>
          </div>

          <p style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)' }}>
            عند التأكيد سيتم:
          </p>
          <ul style={{ fontSize: 'var(--text-sm)', color: 'var(--text-muted)', paddingRight: 'var(--space-4)', display: 'grid', gap: 'var(--space-1)' }}>
            <li>إعادة الكميات إلى المخزون</li>
            <li>إنشاء قيد محاسبي عكسي</li>
            {isCashReturn && <li style={{ color: 'var(--color-warning)', fontWeight: 600 }}>خصم المبلغ من الخزينة/العهدة</li>}
            {!isCashReturn && <li>خصم المبلغ من مديونية العميل تلقائياً</li>}
          </ul>

          {isCashReturn && (
            <>
              <div>
                <label className="form-label">الخزينة (لرد المبلغ) *</label>
                <select className="form-select" value={confirmVaultId}
                  onChange={e => { setConfirmVaultId(e.target.value); setConfirmCustodyId('') }}>
                  <option value="">— اختر خزينة —</option>
                  {vaults.map(v => (
                    <option key={v.id} value={v.id}>
                      {v.name} ({v.type === 'cash' ? 'صندوق' : v.type === 'bank' ? 'بنك' : 'محفظة'})
                    </option>
                  ))}
                </select>
              </div>
              <div style={{ textAlign: 'center', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>— أو —</div>
              <div>
                <label className="form-label">العهدة (لرد المبلغ)</label>
                <select className="form-select" value={confirmCustodyId}
                  onChange={e => { setConfirmCustodyId(e.target.value); setConfirmVaultId('') }}>
                  <option value="">— اختر عهدة —</option>
                  {custodyAccounts.map(c => (
                    <option key={c.id} value={c.id}>
                      {c.employee?.full_name} ({formatNumber(c.current_balance)} ج.م)
                    </option>
                  ))}
                </select>
              </div>
            </>
          )}

          <div className="flex gap-3" style={{ justifyContent: 'flex-end', paddingTop: 'var(--space-3)' }}>
            <Button variant="ghost" onClick={() => setShowConfirm(false)}>إلغاء</Button>
            <Button icon={<CheckCircle size={16} />} onClick={handleConfirm} disabled={actionLoading}>
              {actionLoading ? 'جاري التأكيد...' : 'تأكيد المرتجع'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      {/* ═══════ Cancel Modal ═══════ */}
      <ResponsiveModal open={showCancel} onClose={() => setShowCancel(false)} title="إلغاء المرتجع">
        <div style={{ display: 'grid', gap: 'var(--space-4)' }}>
          <p style={{ color: 'var(--color-danger)', fontSize: 'var(--text-sm)' }}>
            سيتم إلغاء المرتجع. هذا الإجراء لا يمكن التراجع عنه.
          </p>
          <div className="flex gap-3" style={{ justifyContent: 'flex-end' }}>
            <Button variant="ghost" onClick={() => setShowCancel(false)}>تراجع</Button>
            <Button variant="danger" icon={<XCircle size={16} />}
              onClick={handleCancel} disabled={actionLoading}>
              {actionLoading ? 'جاري الإلغاء...' : 'تأكيد الإلغاء'}
            </Button>
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .rtn-table-view { display: block; }
        .rtn-card-view  { display: none; }
        .rtn-desktop-actions { display: flex; gap: 8px; }
        .rtn-action-bar { display: none; }
        @media (max-width: 768px) {
          .rtn-table-view { display: none; }
          .rtn-card-view  { display: block; }
          .rtn-desktop-actions { display: none; }
          .rtn-action-bar {
            display: flex;
            gap: 8px;
            position: fixed;
            bottom: calc(var(--bottom-nav-height, 64px) + env(safe-area-inset-bottom, 0px) + 8px);
            left: 0; right: 0;
            z-index: 200;
            padding: 10px 16px;
            background: var(--bg-surface);
            border-top: 1px solid var(--border-primary);
            box-shadow: 0 -4px 16px rgba(0,0,0,0.08);
          }
        }
      `}</style>
    </div>
  )
}

function InfoRow({ icon, label, value, color, onClick }: {
  icon?: React.ReactNode; label: string; value?: string | null; color?: string; onClick?: () => void
}) {
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
      <span style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
        {icon} {label}
      </span>
      <span
        style={{
          fontWeight: 500, fontSize: 'var(--text-sm)', fontVariantNumeric: 'tabular-nums',
          color: onClick ? 'var(--color-primary)' : (color || 'inherit'),
          cursor: onClick ? 'pointer' : undefined,
          textDecoration: onClick ? 'underline' : undefined,
        }}
        onClick={onClick}
      >
        {value || '—'}
      </span>
    </div>
  )
}
