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
import Modal from '@/components/ui/Modal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

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

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/inventory/adjustments')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للتسويات
          </button>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
            <h1 className="page-title">تسوية {adjustment.number || ''}</h1>
            <Badge variant={st.variant}>{st.label}</Badge>
          </div>
          <p className="page-subtitle">{tp.icon} {tp.label}</p>
        </div>
        <div className="page-actions" style={{ display: 'flex', gap: 'var(--space-2)' }}>
          {adjustment.status === 'pending' && can('inventory.update') && (
            <>
              <Button variant="success" icon={<Check size={14} />} onClick={() => setApproveConfirm(true)}>
                اعتماد
              </Button>
              <Button variant="danger" icon={<XIcon size={14} />} onClick={() => { setRejectReason(''); setRejectModal(true) }}>
                رفض
              </Button>
            </>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(180px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
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
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(250px, 1fr))', gap: 'var(--space-3)' }}>
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
              <th>SKU</th>
              <th>كمية النظام</th>
              <th>الكمية الفعلية</th>
              <th>الفرق</th>
              {canViewCosts && <th>تكلفة الوحدة</th>}
              {canViewCosts && <th>قيمة الفرق</th>}
              <th>ملاحظات</th>
            </tr>
          </thead>
          <tbody>
            {adjustment.items?.map((item: any, idx: number) => {
              const diff = (item.actual_qty || 0) - (item.system_qty || 0)
              return (
                <tr key={item.id}>
                  <td style={{ color: 'var(--text-muted)' }}>{idx + 1}</td>
                  <td style={{ fontWeight: 500 }}>{item.product?.name || item.product_id}</td>
                  <td dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{item.product?.sku || '—'}</td>
                  <td>{formatNumber(item.system_qty)}</td>
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
                  <td style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{item.notes || '—'}</td>
                </tr>
              )
            })}
          </tbody>
          {canViewCosts && adjustment.items && adjustment.items.length > 0 && (
            <tfoot>
              <tr>
                <td colSpan={6} />
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

      {/* Approve Confirm */}
      {approveConfirm && (
        <ConfirmDialog
          open={true}
          title="اعتماد التسوية"
          message={`سيتم تطبيق فروق التسوية ${adjustment.number} على المخزون.\n\n📦 ${adjustment.items?.length || 0} بند${totalIncrease > 0 ? ` | ⬆ زيادة: ${totalIncrease}` : ''}${totalDecrease > 0 ? ` | ⬇ نقص: ${totalDecrease}` : ''}\n\nملاحظة: سيتم إعادة حساب الفروق مع المخزون الحالي لحظة الاعتماد.`}
          variant="info"
          confirmText="اعتماد"
          loading={actionLoading}
          onConfirm={handleApprove}
          onCancel={() => setApproveConfirm(false)}
        />
      )}

      {/* Reject Modal */}
      {rejectModal && (
        <Modal open={true} onClose={() => setRejectModal(false)} title="رفض التسوية" size="sm"
          footer={
            <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
              <Button variant="secondary" onClick={() => setRejectModal(false)}>إلغاء</Button>
              <Button variant="danger" loading={actionLoading} onClick={handleReject}>رفض التسوية</Button>
            </div>
          }
        >
          <div className="form-group">
            <label className="form-label">سبب الرفض (اختياري)</label>
            <textarea className="form-input" rows={3} value={rejectReason}
              onChange={e => setRejectReason(e.target.value)}
              placeholder="اكتب سبب الرفض..."
            />
          </div>
          <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-2)' }}>
            سيتم رفض التسوية {adjustment.number} بدون تطبيق أي تغييرات على المخزون.
          </p>
        </Modal>
      )}
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
