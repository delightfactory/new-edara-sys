import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, ClipboardMinus, Warehouse, User, Calendar,
  Hash, FileText, Check, XIcon, Package, Clock
} from 'lucide-react'
import { getAdjustment, approveAdjustment, rejectAdjustment } from '@/lib/services/inventory'
import { useAuthStore } from '@/stores/auth-store'
import { formatNumber, formatDateShort } from '@/lib/utils/format'
import type { StockAdjustment } from '@/lib/types/master-data'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ResponsiveModal from '@/components/ui/ResponsiveModal'

export default function AdjustmentDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')

  const [loading, setLoading] = useState(true)
  const [adjustment, setAdjustment] = useState<StockAdjustment | null>(null)
  const [actionLoading, setActionLoading] = useState(false)
  const [approveConfirm, setApproveConfirm] = useState(false)
  const [rejectModal, setRejectModal] = useState(false)
  const [rejectReason, setRejectReason] = useState('')

  const load = async () => {
    if (!id) return
    try {
      const a = await getAdjustment(id)
      setAdjustment(a)
    } catch { toast.error('فشل تحميل بيانات التسوية') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [id])

  const handleApprove = async () => {
    if (!adjustment) return
    setActionLoading(true)
    try {
      await approveAdjustment(adjustment.id)
      toast.success('تم اعتماد التسوية وتطبيق الفروق على المخزون')
      load()
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setActionLoading(false); setApproveConfirm(false) }
  }

  const handleReject = async () => {
    if (!adjustment) return
    setActionLoading(true)
    try {
      await rejectAdjustment(adjustment.id, rejectReason || undefined)
      toast.success('تم رفض التسوية')
      setRejectReason('')
      setRejectModal(false)
      load()
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setActionLoading(false) }
  }

  const statusMap: Record<string, { label: string; variant: 'neutral' | 'warning' | 'success' | 'danger' }> = {
    draft: { label: 'مسودة', variant: 'neutral' },
    pending: { label: 'معلق', variant: 'warning' },
    approved: { label: 'معتمد', variant: 'success' },
    rejected: { label: 'مرفوض', variant: 'danger' },
  }

  const typeMap: Record<string, { label: string; icon: string; color: string }> = {
    add: { label: 'إضافة مخزون', icon: '➕', color: 'var(--color-success)' },
    remove: { label: 'إزالة مخزون', icon: '➖', color: 'var(--color-danger)' },
    count: { label: 'جرد (مقارنة)', icon: '📋', color: 'var(--color-info)' },
  }

  if (loading) return (
    <div className="page-container animate-enter">
      {[1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) 0' }} />)}
    </div>
  )

  if (!adjustment) return (
    <div className="page-container animate-enter">
      <div className="empty-state">
        <ClipboardMinus size={48} className="empty-state-icon" />
        <p className="empty-state-title">التسوية غير موجودة</p>
        <button className="btn btn-primary" onClick={() => navigate('/inventory/adjustments')}>العودة للتسويات</button>
      </div>
    </div>
  )

  const st = statusMap[adjustment.status] || { label: adjustment.status, variant: 'neutral' as const }
  const tp = typeMap[adjustment.type] || { label: adjustment.type, icon: '📦', color: 'var(--text-primary)' }

  // Compute impact
  let totalIncrease = 0, totalDecrease = 0
  adjustment.items?.forEach((it: any) => {
    const diff = (it.actual_qty || 0) - (it.system_qty || 0)
    if (diff > 0) totalIncrease += diff
    else if (diff < 0) totalDecrease += Math.abs(diff)
  })

  const statusColors: Record<string, string> = {
    draft: '#6b7280', pending: '#f59e0b', approved: '#16a34a', rejected: '#dc2626',
  }
  const sc = statusColors[adjustment.status] || '#6b7280'

  return (
    <div style={{ maxWidth: 900, margin: '0 auto', paddingBottom: 120 }}>

      {/* ══ Sticky Mobile Hero ══ */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 10,
        background: `linear-gradient(135deg, ${sc}12, ${sc}06)`,
        borderBottom: `3px solid ${sc}30`,
        backdropFilter: 'blur(12px)',
        padding: '14px 16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <button onClick={() => navigate('/inventory/adjustments')}
            style={{ background: 'var(--bg-surface)', border: '1px solid var(--border-primary)', borderRadius: 10, padding: '7px 10px', cursor: 'pointer', display: 'flex', alignItems: 'center', gap: 4, fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0 }}>
            <ArrowRight size={14} /> رجوع
          </button>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 17, fontWeight: 800, margin: 0 }}>تسوية {adjustment.number || ''}</h1>
              <Badge variant={st.variant}>{st.label}</Badge>
            </div>
            <div style={{ fontSize: 12, color: 'var(--text-muted)', marginTop: 2 }}>
              {tp.icon} {tp.label}
              {totalIncrease > 0 && <span style={{ marginRight: 8, color: 'var(--color-success)' }}> ⬆ +{formatNumber(totalIncrease)}</span>}
              {totalDecrease > 0 && <span style={{ color: 'var(--color-danger)' }}> ⬇ -{formatNumber(totalDecrease)}</span>}
            </div>
          </div>
          {/* Desktop actions */}
          {adjustment.status === 'pending' && can('inventory.update') && (
            <div className="adj-desktop-actions" style={{ display: 'flex', gap: 8, flexShrink: 0 }}>
              <Button variant="success" icon={<Check size={14} />} onClick={() => setApproveConfirm(true)}>اعتماد</Button>
              <Button variant="danger" icon={<XIcon size={14} />} onClick={() => { setRejectReason(''); setRejectModal(true) }}>رفض</Button>
            </div>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 'var(--space-3)', margin: '12px 12px', marginBottom: 'var(--space-4)' }}>
        {/* المخزن */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-primary-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Warehouse size={16} style={{ color: 'var(--color-primary)' }} />
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>المخزن</span>
          </div>
          <div style={{ fontSize: 'var(--text-base)', fontWeight: 600 }}>{adjustment.warehouse?.name || '—'}</div>
        </div>

        {/* عدد البنود */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-info-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Package size={16} style={{ color: 'var(--color-info)' }} />
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>عدد البنود</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>{adjustment.items?.length || 0}</div>
        </div>

        {/* زيادة */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-success-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span style={{ fontSize: 14, color: 'var(--color-success)' }}>⬆</span>
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>زيادة</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: totalIncrease > 0 ? 'var(--color-success)' : 'var(--text-muted)' }}>
            {totalIncrease > 0 ? `+${formatNumber(totalIncrease)}` : '0'}
          </div>
        </div>

        {/* نقص */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-danger-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <span style={{ fontSize: 14, color: 'var(--color-danger)' }}>⬇</span>
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>نقص</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700, color: totalDecrease > 0 ? 'var(--color-danger)' : 'var(--text-muted)' }}>
            {totalDecrease > 0 ? `-${formatNumber(totalDecrease)}` : '0'}
          </div>
        </div>
      </div>

      {/* Content Grid: Info */}
      <div className="edara-card" style={{ padding: 'var(--space-5)', marginBottom: 'var(--space-4)' }}>
        <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>معلومات التسوية</h2>
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 'var(--space-3)' }}>
          <InfoRow icon={User} label="أنشأ بواسطة" value={(adjustment as any).created_by_profile?.full_name} />
          <InfoRow icon={Calendar} label="تاريخ الإنشاء" value={formatDateShort(adjustment.created_at)} />
          <InfoRow icon={ClipboardMinus} label="النوع" value={tp.label} />
          <InfoRow icon={Clock} label="آخر تحديث" value={formatDateShort(adjustment.updated_at)} />
          {(adjustment as any).approved_by && (
            <InfoRow icon={Check} label={adjustment.status === 'rejected' ? 'رفض بواسطة' : 'اعتمد بواسطة'}
              value={(adjustment as any).approved_by_profile?.full_name || '—'} />
          )}
          {adjustment.status === 'rejected' && (adjustment as any).rejection_reason && (
            <InfoRow icon={XIcon} label="سبب الرفض" value={(adjustment as any).rejection_reason} />
          )}
        </div>
        {adjustment.reason && (
          <div style={{ marginTop: 'var(--space-4)', padding: 'var(--space-3)', background: 'var(--bg-secondary)', borderRadius: 'var(--radius-md)' }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-1)' }}>السبب</div>
            <div style={{ fontSize: 'var(--text-sm)' }}>{adjustment.reason}</div>
          </div>
        )}
      </div>

      {/* Items Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)' }}>
          <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>بنود التسوية</h2>
        </div>
        <table className="data-table">
          <thead>
            <tr>
              <th style={{ width: 40 }}>#</th>
              <th>المنتج</th>
              <th className="hide-mobile">SKU</th>
              <th className="hide-mobile">كمية النظام</th>
              <th>الكمية الفعلية</th>
              <th>الفرق</th>
              {canViewCosts && <th>تكلفة الوحدة</th>}
              {canViewCosts && <th>قيمة الفرق</th>}
              <th className="hide-mobile">ملاحظات</th>
            </tr>
          </thead>
          <tbody>
            {adjustment.items?.map((item: any, idx: number) => {
              const diff = (item.actual_qty || 0) - (item.system_qty || 0)
              return (
                <tr key={item.id}>
                  <td style={{ color: 'var(--text-muted)' }}>{idx + 1}</td>
                  <td style={{ fontWeight: 500 }}>{item.product?.name || item.product_id}</td>
                  <td className="hide-mobile" dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{item.product?.sku || '—'}</td>
                  <td className="hide-mobile">{formatNumber(item.system_qty)}</td>
                  <td style={{ fontWeight: 600 }}>{formatNumber(item.actual_qty)}</td>
                  <td style={{
                    fontWeight: 700,
                    color: diff > 0 ? 'var(--color-success)' : diff < 0 ? 'var(--color-danger)' : 'var(--text-muted)'
                  }}>
                    {diff > 0 ? `+${formatNumber(diff)}` : diff === 0 ? '—' : formatNumber(diff)}
                  </td>
                  {canViewCosts && <td>{item.unit_cost ? formatNumber(item.unit_cost) : '—'}</td>}
                  {canViewCosts && (
                    <td style={{
                      fontWeight: 600,
                      color: diff > 0 ? 'var(--color-success)' : diff < 0 ? 'var(--color-danger)' : 'var(--text-muted)'
                    }}>
                      {item.unit_cost && diff !== 0 ? `${diff > 0 ? '+' : ''}${formatNumber(diff * item.unit_cost)}` : '—'}
                    </td>
                  )}
                  <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{item.notes || '—'}</td>
                </tr>
              )
            })}
          </tbody>
          {canViewCosts && adjustment.items && adjustment.items.length > 0 && (
            <tfoot>
              <tr>
                <td colSpan={4} className="hide-mobile" /><td colSpan={2} />
                <td style={{ fontWeight: 700 }}>الإجمالي</td>
                <td style={{ fontWeight: 700 }}>
                  {(() => {
                    const total = adjustment.items!.reduce((sum: number, it: any) => {
                      const diff = (it.actual_qty || 0) - (it.system_qty || 0)
                      return sum + diff * (it.unit_cost || 0)
                    }, 0)
                    return (
                      <span style={{ color: total > 0 ? 'var(--color-success)' : total < 0 ? 'var(--color-danger)' : 'var(--text-primary)' }}>
                        {total > 0 ? '+' : ''}{formatNumber(total)}
                      </span>
                    )
                  })()}
                </td>
                <td />
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      {/* ══ Mobile Action Bar ══ */}
      {adjustment.status === 'pending' && can('inventory.update') && (
        <div className="adj-action-bar">
          <button type="button" className="btn btn-success"
            style={{ flex: 1, display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6 }}
            onClick={() => setApproveConfirm(true)}>
            <Check size={15} /> اعتماد التسوية
          </button>
          <button type="button" className="btn btn-danger"
            style={{ flex: '0 0 auto', paddingInline: 16, display: 'flex', alignItems: 'center', gap: 5 }}
            onClick={() => { setRejectReason(''); setRejectModal(true) }}>
            <XIcon size={15} /> رفض
          </button>
        </div>
      )}

      {/* ══ Approve Confirm Modal ══ */}
      <ResponsiveModal open={approveConfirm} onClose={() => setApproveConfirm(false)} title="اعتماد التسوية">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div style={{
            padding: '12px 14px', borderRadius: 10,
            background: 'var(--color-info-light, #eff6ff)',
            border: '1px solid var(--color-info, #3b82f6)', fontSize: 13,
          }}>
            سيتم تطبيق فروق التسوية {adjustment.number} على المخزون.
            <br />
            📦 {adjustment.items?.length || 0} بند
            {totalIncrease > 0 && ` | ⬆ زيادة: ${totalIncrease}`}
            {totalDecrease > 0 && ` | ⬇ نقص: ${totalDecrease}`}
          </div>
          <p style={{ fontSize: 12, color: 'var(--text-muted)', margin: 0 }}>
            سيتم إعادة حساب الفروق مع المخزون الحالي لحظة الاعتماد.
          </p>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button type="button" className="btn btn-secondary" onClick={() => setApproveConfirm(false)} disabled={actionLoading}>إلغاء</button>
            <button type="button" className="btn btn-success" onClick={handleApprove} disabled={actionLoading}
              style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
              <Check size={14} /> {actionLoading ? 'جاري...' : 'اعتماد'}
            </button>
          </div>
        </div>
      </ResponsiveModal>

      {/* ══ Reject Modal ══ */}
      <ResponsiveModal open={rejectModal} onClose={() => setRejectModal(false)} title="رفض التسوية">
        <div style={{ display: 'flex', flexDirection: 'column', gap: 14 }}>
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label">سبب الرفض (اختياري)</label>
            <textarea className="form-input" rows={3} value={rejectReason}
              onChange={e => setRejectReason(e.target.value)}
              placeholder="اكتب سبب الرفض..."
            />
          </div>
          <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', margin: 0 }}>
            سيتم رفض التسوية {adjustment.number} بدون تطبيق أي تغييرات على المخزون.
          </p>
          <div style={{ display: 'flex', gap: 10, justifyContent: 'flex-end' }}>
            <button type="button" className="btn btn-secondary" onClick={() => setRejectModal(false)} disabled={actionLoading}>إلغاء</button>
            <Button variant="danger" loading={actionLoading} onClick={handleReject}>رفض التسوية</Button>
          </div>
        </div>
      </ResponsiveModal>

      <style>{`
        .adj-desktop-actions { display: flex !important; }
        .adj-action-bar { display: none; }
        @media (max-width: 768px) {
          .adj-desktop-actions { display: none !important; }
          .adj-action-bar {
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

/* Helper */
function InfoRow({ icon: Icon, label, value }: { icon: any; label: string; value: string | null | undefined }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', padding: 'var(--space-2) 0', borderBottom: '1px solid var(--border-secondary)' }}>
      <Icon size={14} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
      <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', minWidth: 90 }}>{label}</span>
      <span style={{ fontSize: 'var(--text-sm)', fontWeight: 500 }}>{value || '—'}</span>
    </div>
  )
}
