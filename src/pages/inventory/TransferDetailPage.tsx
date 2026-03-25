import { useState, useEffect } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, ArrowLeftRight, Warehouse, User, Calendar, Hash,
  FileText, Check, XIcon, Truck, Package, Clock
} from 'lucide-react'
import { getTransfer, getMyWarehouses, shipTransfer, approveAndShipTransfer, receiveTransfer, cancelTransfer } from '@/lib/services/inventory'
import { useAuthStore } from '@/stores/auth-store'
import { formatNumber, formatDateShort } from '@/lib/utils/format'
import type { StockTransfer } from '@/lib/types/master-data'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

export default function TransferDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)
  const canViewCosts = can('finance.view_costs')
  const isAdmin = can('inventory.read_all')

  const [loading, setLoading] = useState(true)
  const [transfer, setTransfer] = useState<StockTransfer | null>(null)
  const [actionLoading, setActionLoading] = useState(false)
  const [confirmAction, setConfirmAction] = useState<{ type: 'ship' | 'approve' | 'receive' | 'cancel' } | null>(null)
  const [myWarehouses, setMyWarehouses] = useState<any[]>([])

  const load = async () => {
    if (!id) return
    try {
      const [t, myWhs] = await Promise.all([
        getTransfer(id),
        myWarehouses.length ? Promise.resolve(myWarehouses) : getMyWarehouses(),
      ])
      setTransfer(t)
      if (!myWarehouses.length) setMyWarehouses(myWhs)
    } catch { toast.error('فشل تحميل بيانات التحويل') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [id])

  const isMyWarehouse = (whId: string) =>
    isAdmin || myWarehouses.some((w: any) => w.id === whId)

  const handleAction = async () => {
    if (!confirmAction || !transfer) return
    setActionLoading(true)
    try {
      if (confirmAction.type === 'ship') {
        await shipTransfer(transfer.id)
        toast.success('تم الشحن بنجاح')
      } else if (confirmAction.type === 'approve') {
        await approveAndShipTransfer(transfer.id)
        toast.success('تمت الموافقة والشحن')
      } else if (confirmAction.type === 'receive') {
        await receiveTransfer(transfer.id)
        toast.success('تم تأكيد الاستلام')
      } else if (confirmAction.type === 'cancel') {
        await cancelTransfer(transfer.id)
        toast.success('تم إلغاء التحويل')
      }
      load()
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setActionLoading(false); setConfirmAction(null) }
  }

  const statusMap: Record<string, { label: string; variant: 'neutral' | 'warning' | 'success' | 'danger' | 'info' }> = {
    pending: { label: 'في الانتظار', variant: 'warning' },
    in_transit: { label: 'قيد الشحن', variant: 'info' },
    received: { label: 'تم الاستلام', variant: 'success' },
    cancelled: { label: 'ملغي', variant: 'danger' },
  }

  const directionMap: Record<string, { label: string; icon: string }> = {
    push: { label: 'إرسال (Push)', icon: '📤' },
    pull: { label: 'طلب (Pull)', icon: '📥' },
  }

  if (loading) return (
    <div className="page-container animate-enter">
      {[1, 2, 3, 4].map(i => <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) 0' }} />)}
    </div>
  )

  if (!transfer) return (
    <div className="page-container animate-enter">
      <div className="empty-state">
        <ArrowLeftRight size={48} className="empty-state-icon" />
        <p className="empty-state-title">التحويل غير موجود</p>
        <button className="btn btn-primary" onClick={() => navigate('/inventory/transfers')}>العودة للتحويلات</button>
      </div>
    </div>
  )

  const st = statusMap[transfer.status] || { label: transfer.status, variant: 'neutral' as const }
  const dir = directionMap[transfer.direction] || { label: transfer.direction, icon: '↔' }

  const canApprove = transfer.status === 'pending' && transfer.direction === 'pull' && isMyWarehouse(transfer.from_warehouse_id)
  const canShip = transfer.status === 'pending' && transfer.direction === 'push' && isMyWarehouse(transfer.from_warehouse_id)
  const canReceive = transfer.status === 'in_transit' && isMyWarehouse(transfer.to_warehouse_id)
  const canCancel = (transfer.status === 'pending' || transfer.status === 'in_transit') && (
    isMyWarehouse(transfer.from_warehouse_id) ||
    (transfer.status === 'pending' && transfer.direction === 'pull' && isMyWarehouse(transfer.to_warehouse_id))
  )

  // Timeline
  const timeline: { label: string; date: string | null; icon: any; active: boolean }[] = [
    { label: 'تم الإنشاء', date: transfer.created_at, icon: FileText, active: true },
    { label: 'تم الشحن', date: (transfer as any).shipped_at || (transfer.status !== 'pending' && transfer.status !== 'cancelled' ? transfer.updated_at : null), icon: Truck, active: ['in_transit', 'received'].includes(transfer.status) },
    { label: 'تم الاستلام', date: transfer.status === 'received' ? transfer.updated_at : null, icon: Check, active: transfer.status === 'received' },
  ]

  return (
    <div className="page-container animate-enter">
      {/* Header */}
      <div className="page-header">
        <div className="page-header-info">
          <button className="btn btn-ghost btn-sm" onClick={() => navigate('/inventory/transfers')} style={{ marginBottom: 'var(--space-2)' }}>
            <ArrowRight size={14} /> العودة للتحويلات
          </button>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-3)' }}>
            <h1 className="page-title">تحويل {transfer.number || ''}</h1>
            <Badge variant={st.variant}>{st.label}</Badge>
          </div>
          <p className="page-subtitle">{dir.icon} {dir.label}</p>
        </div>
        <div className="page-actions" style={{ display: 'flex', gap: 'var(--space-2)', flexWrap: 'wrap' }}>
          {canShip && (
            <Button variant="primary" icon={<Truck size={14} />} onClick={() => setConfirmAction({ type: 'ship' })}>
              شحن
            </Button>
          )}
          {canApprove && (
            <Button variant="primary" icon={<Truck size={14} />} onClick={() => setConfirmAction({ type: 'approve' })}>
              موافقة وشحن
            </Button>
          )}
          {canReceive && (
            <Button variant="success" icon={<Check size={14} />} onClick={() => setConfirmAction({ type: 'receive' })}>
              تأكيد الاستلام
            </Button>
          )}
          {canCancel && (
            <Button variant="danger" icon={<XIcon size={14} />} onClick={() => setConfirmAction({ type: 'cancel' })}>
              إلغاء
            </Button>
          )}
        </div>
      </div>

      {/* Summary Cards */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))', gap: 'var(--space-3)', marginBottom: 'var(--space-4)' }}>
        {/* من مخزن */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-danger-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Warehouse size={16} style={{ color: 'var(--color-danger)' }} />
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>من مخزن</span>
          </div>
          <div style={{ fontSize: 'var(--text-base)', fontWeight: 600 }}>{(transfer as any).from_warehouse?.name || '—'}</div>
        </div>

        {/* إلى مخزن */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-success-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Warehouse size={16} style={{ color: 'var(--color-success)' }} />
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>إلى مخزن</span>
          </div>
          <div style={{ fontSize: 'var(--text-base)', fontWeight: 600 }}>{(transfer as any).to_warehouse?.name || '—'}</div>
        </div>

        {/* عدد البنود */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-info-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Package size={16} style={{ color: 'var(--color-info)' }} />
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>عدد البنود</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>{transfer.items?.length || 0}</div>
        </div>

        {/* إجمالي الكميات */}
        <div className="edara-card" style={{ padding: 'var(--space-4)' }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 'var(--space-2)', marginBottom: 'var(--space-2)' }}>
            <div style={{ width: 32, height: 32, borderRadius: 'var(--radius-md)', background: 'var(--color-warning-light)', display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
              <Hash size={16} style={{ color: 'var(--color-warning)' }} />
            </div>
            <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>إجمالي الكميات</span>
          </div>
          <div style={{ fontSize: 'var(--text-xl)', fontWeight: 700 }}>
            {formatNumber(transfer.items?.reduce((sum: number, it: any) => sum + (it.quantity || 0), 0) || 0)}
          </div>
        </div>
      </div>

      {/* Content Grid: Info + Timeline */}
      <div className="detail-grid" style={{ marginBottom: 'var(--space-4)' }}>
        {/* Info Card */}
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>معلومات التحويل</h2>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(200px, 1fr))', gap: 'var(--space-3)' }}>
            <InfoRow icon={User} label="طالب التحويل" value={(transfer as any).requested_by_profile?.full_name} />
            <InfoRow icon={Calendar} label="تاريخ الإنشاء" value={formatDateShort(transfer.created_at)} />
            <InfoRow icon={ArrowLeftRight} label="الاتجاه" value={dir.label} />
            <InfoRow icon={Clock} label="آخر تحديث" value={formatDateShort(transfer.updated_at)} />
            {(transfer as any).cancelled_by && (
              <>
                <InfoRow icon={XIcon} label="ملغي بواسطة" value={(transfer as any).cancelled_by_profile?.full_name || '—'} />
                <InfoRow icon={Calendar} label="تاريخ الإلغاء" value={(transfer as any).cancelled_at ? formatDateShort((transfer as any).cancelled_at) : '—'} />
              </>
            )}
          </div>
          {transfer.notes && (
            <div style={{ marginTop: 'var(--space-4)', padding: 'var(--space-3)', background: 'var(--bg-secondary)', borderRadius: 'var(--radius-md)' }}>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-1)' }}>ملاحظات</div>
              <div style={{ fontSize: 'var(--text-sm)' }}>{transfer.notes}</div>
            </div>
          )}
        </div>

        {/* Timeline Card */}
        <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
          <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>المراحل</h2>
          <div style={{ display: 'flex', flexDirection: 'column', gap: 0 }}>
            {timeline.map((step, idx) => (
              <div key={idx} style={{ display: 'flex', gap: 'var(--space-3)', position: 'relative', paddingBottom: idx < timeline.length - 1 ? 'var(--space-5)' : 0 }}>
                {/* Line */}
                {idx < timeline.length - 1 && (
                  <div style={{
                    position: 'absolute', right: 15, top: 32, width: 2, bottom: 0,
                    background: step.active && timeline[idx + 1]?.active ? 'var(--color-primary)' : 'var(--border-primary)'
                  }} />
                )}
                {/* Icon */}
                <div style={{
                  width: 32, height: 32, borderRadius: '50%', flexShrink: 0,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: step.active ? 'var(--color-primary)' : 'var(--bg-surface-2)',
                  color: step.active ? '#fff' : 'var(--text-muted)',
                  zIndex: 1,
                }}>
                  <step.icon size={14} />
                </div>
                {/* Content */}
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{ fontSize: 'var(--text-sm)', fontWeight: step.active ? 600 : 400, color: step.active ? 'var(--text-primary)' : 'var(--text-muted)' }}>
                    {step.label}
                  </div>
                  {step.date && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
                      {formatDateShort(step.date)}
                    </div>
                  )}
                </div>
              </div>
            ))}
            {transfer.status === 'cancelled' && (
              <div style={{ display: 'flex', gap: 'var(--space-3)', paddingTop: 'var(--space-3)' }}>
                <div style={{
                  width: 32, height: 32, borderRadius: '50%', flexShrink: 0,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  background: 'var(--color-danger-light)', color: 'var(--color-danger)', zIndex: 1,
                }}>
                  <XIcon size={14} />
                </div>
                <div>
                  <div style={{ fontSize: 'var(--text-sm)', fontWeight: 600, color: 'var(--color-danger)' }}>ملغي</div>
                  {(transfer as any).cancelled_at && (
                    <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
                      {formatDateShort((transfer as any).cancelled_at)}
                    </div>
                  )}
                </div>
              </div>
            )}
          </div>
        </div>
      </div>

      {/* Items Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        <div style={{ padding: 'var(--space-4) var(--space-5)', borderBottom: '1px solid var(--border-primary)' }}>
          <h2 style={{ fontSize: 'var(--text-lg)', fontWeight: 700 }}>بنود التحويل</h2>
        </div>
        <table className="data-table">
          <thead>
            <tr>
              <th style={{ width: 40 }}>#</th>
              <th>المنتج</th>
              <th className="hide-mobile">SKU</th>
              <th className="hide-mobile">الوحدة</th>
              <th>الكمية</th>
              {canViewCosts && <th>تكلفة الوحدة (WAC)</th>}
              {canViewCosts && <th>الإجمالي</th>}
            </tr>
          </thead>
          <tbody>
            {transfer.items?.map((item: any, idx: number) => (
              <tr key={item.id}>
                <td style={{ color: 'var(--text-muted)' }}>{idx + 1}</td>
                <td style={{ fontWeight: 500 }}>{item.product?.name || item.product_id}</td>
                <td className="hide-mobile" dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{item.product?.sku || '—'}</td>
                <td className="hide-mobile">{item.unit?.name || '—'}</td>
                <td style={{ fontWeight: 600 }}>{formatNumber(item.quantity)}</td>
                {canViewCosts && <td>{item.unit_cost ? formatNumber(item.unit_cost) : '—'}</td>}
                {canViewCosts && <td style={{ fontWeight: 600 }}>{item.unit_cost ? formatNumber(item.quantity * item.unit_cost) : '—'}</td>}
              </tr>
            ))}
          </tbody>
          {canViewCosts && transfer.items && transfer.items.length > 0 && (
            <tfoot>
              <tr>
                <td colSpan={3} className="hide-mobile" /><td colSpan={2} />
                <td style={{ fontWeight: 700 }}>الإجمالي</td>
                <td style={{ fontWeight: 700 }}>
                  {formatNumber(transfer.items.reduce((sum: number, it: any) => sum + (it.quantity * (it.unit_cost || 0)), 0))}
                </td>
              </tr>
            </tfoot>
          )}
        </table>
      </div>

      {/* Confirm Dialogs */}
      {confirmAction && (
        <ConfirmDialog
          open={true}
          title={
            confirmAction.type === 'ship' ? 'تأكيد الشحن' :
            confirmAction.type === 'approve' ? 'موافقة وشحن' :
            confirmAction.type === 'receive' ? 'تأكيد الاستلام' : 'إلغاء التحويل'
          }
          message={
            confirmAction.type === 'ship'
              ? `سيتم شحن التحويل ${transfer.number || ''} وخصم الكميات من المخزن المُرسل.`
              : confirmAction.type === 'approve'
              ? `سيتم الموافقة على التحويل ${transfer.number || ''} وشحنه. سيتم حجز الكميات من المخزن المُرسل.`
              : confirmAction.type === 'receive'
              ? `سيتم تأكيد استلام التحويل ${transfer.number || ''} وإضافة الكميات للمخزن المُستلم.`
              : `سيتم إلغاء التحويل ${transfer.number || ''} وإلغاء حجز الكميات.`
          }
          variant={confirmAction.type === 'cancel' ? 'danger' : 'info'}
          confirmText={
            confirmAction.type === 'ship' ? 'شحن' :
            confirmAction.type === 'approve' ? 'موافقة وشحن' :
            confirmAction.type === 'receive' ? 'تأكيد الاستلام' : 'إلغاء'
          }
          loading={actionLoading}
          onConfirm={handleAction}
          onCancel={() => setConfirmAction(null)}
        />
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
