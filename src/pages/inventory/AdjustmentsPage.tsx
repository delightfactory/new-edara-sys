import { useState, Fragment, useMemo } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import { ClipboardMinus, Check, X as XIcon, Plus, ChevronDown, ChevronUp } from 'lucide-react'
import {
  createAdjustment, approveAdjustment, rejectAdjustment,
  getMyWarehouses, getAvailableStock
} from '@/lib/services/inventory'
import { getProducts } from '@/lib/services/products'
import { getStock } from '@/lib/services/inventory'
import { useAdjustments, useWarehouses, useInvalidate } from '@/hooks/useQueryHooks'
import { useQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type { StockAdjustment, Warehouse, AdjustmentType, Product } from '@/lib/types/master-data'
import { formatNumber, formatDateShort } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

export default function AdjustmentsPage() {
  const can = useAuthStore(s => s.can)
  const navigate = useNavigate()
  const invalidate = useInvalidate()
  const canViewCosts = can('finance.view_costs')
  const isAdmin = can('inventory.read_all')
  const [statusFilter, setStatusFilter] = useState('')
  const [whFilter, setWhFilter] = useState('')
  const [page, setPage] = useState(1)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const [rejectReason, setRejectReason] = useState('')

  // React Query — cached & shared
  const { data: warehouses = [] } = useWarehouses()
  const { data: myWarehousesData = [] } = useQuery({
    queryKey: ['my-warehouses'],
    queryFn: () => getMyWarehouses(),
    staleTime: 5 * 60 * 1000,
  })
  const myWarehouses = myWarehousesData as Warehouse[]

  const queryParams = useMemo(() => ({
    status: statusFilter || undefined, warehouseId: whFilter || undefined, page, pageSize: 25,
  }), [statusFilter, whFilter, page])

  const { data: result, isLoading: loading } = useAdjustments(queryParams)
  const adjustments = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0
  // Create modal
  const [createModal, setCreateModal] = useState(false)
  const [createForm, setCreateForm] = useState({ warehouse_id: '', type: 'count' as AdjustmentType, reason: '' })
  const [createItems, setCreateItems] = useState<{
    product_id: string; system_qty: number; actual_qty: number; qty_change: number; unit_cost: number; notes: string
  }[]>([])
  const [products, setProducts] = useState<Product[]>([])
  const [createSaving, setCreateSaving] = useState(false)

  // Confirm dialogs
  const [confirmTarget, setConfirmTarget] = useState<{ adj: StockAdjustment; action: 'approve' | 'reject' } | null>(null)
  const [actionLoading, setActionLoading] = useState(false)
  const [rejectModal, setRejectModal] = useState<StockAdjustment | null>(null)


  const openCreate = async () => {
    setCreateForm({ warehouse_id: '', type: 'count', reason: '' })
    setCreateItems([{ product_id: '', system_qty: 0, actual_qty: 0, qty_change: 0, unit_cost: 0, notes: '' }])
    if (!products.length) {
      const p = await getProducts({ pageSize: 500 })
      setProducts(p.data)
    }
    setCreateModal(true)
  }

  const addItem = () => setCreateItems(i => [...i, { product_id: '', system_qty: 0, actual_qty: 0, qty_change: 0, unit_cost: 0, notes: '' }])
  const removeItem = (idx: number) => setCreateItems(i => i.filter((_, j) => j !== idx))
  const updateItem = (idx: number, key: string, val: any) =>
    setCreateItems(items => items.map((item, j) => j === idx ? { ...item, [key]: val } : item))

  // عند اختيار منتج: ملء system_qty + unit_cost تلقائياً من المخزون الحالي
  const handleProductChange = async (idx: number, productId: string) => {
    updateItem(idx, 'product_id', productId)
    if (productId && createForm.warehouse_id) {
      try {
        const stockRes = await getStock({ warehouseId: createForm.warehouse_id, productId, pageSize: 1 })
        const stockRow = stockRes.data[0]
        const stockQty = stockRow?.quantity || 0
        const stockWac = stockRow?.wac || 0
        setCreateItems(items => items.map((item, j) => j === idx ? {
          ...item, product_id: productId, system_qty: stockQty,
          unit_cost: item.unit_cost === 0 ? stockWac : item.unit_cost
        } : item))
      } catch {
        updateItem(idx, 'system_qty', 0)
      }
    }
  }

  // عند تغيير المخزن: إعادة تحميل system_qty لكل البنود
  const handleWarehouseChange = async (whId: string) => {
    setCreateForm(f => ({ ...f, warehouse_id: whId }))
    if (whId) {
      const updatedItems = await Promise.all(
        createItems.map(async (item) => {
          if (item.product_id) {
            try {
              const stockRes = await getStock({ warehouseId: whId, productId: item.product_id, pageSize: 1 })
              const stockRow = stockRes.data[0]
              return { ...item, system_qty: stockRow?.quantity || 0, unit_cost: stockRow?.wac || item.unit_cost }
            } catch { return { ...item, system_qty: 0 } }
          }
          return item
        })
      )
      setCreateItems(updatedItems)
    }
  }

  // عند تغيير النوع: إعادة حساب actual_qty لكل البنود
  const handleTypeChange = (newType: AdjustmentType) => {
    setCreateForm(f => ({ ...f, type: newType }))
    setCreateItems(items => items.map(item => {
      if (!item.product_id) return { ...item, qty_change: 0, actual_qty: 0 }
      if (newType === 'count') return { ...item, actual_qty: item.system_qty, qty_change: 0 }
      return { ...item, qty_change: 0, actual_qty: item.system_qty }
    }))
  }

  // حساب actual_qty حسب النوع
  const computeActualQty = (type: AdjustmentType, systemQty: number, qtyChange: number, actualQty: number) => {
    if (type === 'count') return actualQty
    if (type === 'add') return systemQty + qtyChange
    if (type === 'remove') return Math.max(systemQty - qtyChange, 0)
    return actualQty
  }

  const handleCreate = async () => {
    if (!createForm.warehouse_id) { toast.error('يرجى اختيار المخزن'); return }
    const validItems = createItems.filter(i => i.product_id)
    if (!validItems.length) { toast.error('يرجى إضافة بنود'); return }

    // validation per type
    for (const item of validItems) {
      if (createForm.type === 'add' && item.qty_change <= 0) {
        toast.error('كمية الإضافة يجب أن تكون أكبر من صفر'); return
      }
      if (createForm.type === 'remove' && item.qty_change <= 0) {
        toast.error('كمية الإزالة يجب أن تكون أكبر من صفر'); return
      }
      if (createForm.type === 'remove' && item.qty_change > item.system_qty) {
        toast.error('لا يمكن إزالة كمية أكبر من المتاح'); return
      }
    }

    // compute actual_qty for API
    const apiItems = validItems.map(item => ({
      product_id: item.product_id,
      actual_qty: computeActualQty(createForm.type, item.system_qty, item.qty_change, item.actual_qty),
      unit_cost: item.unit_cost || undefined,
      notes: item.notes || undefined,
    }))

    setCreateSaving(true)
    try {
      await createAdjustment(createForm, apiItems)
      toast.success('تم إنشاء التسوية')
      setCreateModal(false)
      invalidate('adjustments')
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setCreateSaving(false) }
  }

  const executeAction = async () => {
    if (!confirmTarget) return
    setActionLoading(true)
    try {
      if (confirmTarget.action === 'approve') {
        await approveAdjustment(confirmTarget.adj.id)
        toast.success('تم اعتماد التسوية وتطبيق الفروق على المخزون')
      }
      invalidate('adjustments')
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setActionLoading(false); setConfirmTarget(null) }
  }

  const executeReject = async () => {
    if (!rejectModal) return
    setActionLoading(true)
    try {
      await rejectAdjustment(rejectModal.id, rejectReason || undefined)
      toast.success('تم رفض التسوية')
      setRejectReason('')
      setRejectModal(null)
      invalidate('adjustments')
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setActionLoading(false) }
  }

  // حساب ملخص التأثير
  const getImpactSummary = (adj: StockAdjustment) => {
    if (!adj.items) return null
    let increases = 0, decreases = 0
    adj.items.forEach((it: any) => {
      const diff = it.actual_qty - it.system_qty
      if (diff > 0) increases += diff
      else if (diff < 0) decreases += Math.abs(diff)
    })
    return { count: adj.items.length, increases, decreases }
  }

  const statusMap: Record<string, { label: string; variant: 'neutral' | 'warning' | 'success' | 'danger' }> = {
    draft: { label: 'مسودة', variant: 'neutral' },
    pending: { label: 'معلق', variant: 'warning' },
    approved: { label: 'معتمد', variant: 'success' },
    rejected: { label: 'مرفوض', variant: 'danger' },
  }

  const typeMap: Record<string, string> = { add: 'إضافة', remove: 'إزالة', count: 'جرد' }
  const typeDescriptions: Record<string, string> = {
    count: 'مقارنة الكمية الفعلية بكمية النظام وتطبيق الفرق',
    add: 'إضافة كمية محددة إلى المخزون الحالي',
    remove: 'إزالة كمية محددة من المخزون الحالي',
  }

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="تسويات المخزون"
        subtitle={loading ? '...' : `${totalCount} تسوية`}
        actions={can('inventory.adjustments.create') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate}>تسوية جديدة</Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <div className="flex gap-4" style={{ flexWrap: 'wrap' }}>
          <select className="form-select" style={{ width: 160 }} value={whFilter}
            onChange={e => { setWhFilter(e.target.value); setPage(1) }}>
            <option value="">كل المخازن</option>
            {warehouses.map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
          </select>
          <select className="form-select" style={{ width: 140 }} value={statusFilter}
            onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
            <option value="">كل الحالات</option>
            {Object.entries(statusMap).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
          </select>
        </div>
      </div>

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : adjustments.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <ClipboardMinus size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد تسويات</p>
            <p className="empty-state-text">أنشئ تسوية جديدة لتعديل أرصدة المخزون</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th style={{ width: 30 }}></th>
                <th>الرقم</th>
                <th>المخزن</th>
                <th>النوع</th>
                <th className="hide-mobile">بواسطة</th>
                <th className="hide-mobile">التاريخ</th>
                <th>الحالة</th>
                <th className="hide-mobile">السبب</th>
                <th style={{ width: 130 }}>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {adjustments.map(a => (
                <Fragment key={a.id}>
                  <tr>
                    <td>
                      <Button variant="ghost" size="sm" onClick={() => setExpandedId(expandedId === a.id ? null : a.id)}>
                        {expandedId === a.id ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                      </Button>
                    </td>
                    <td>
                      <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--color-primary)', cursor: 'pointer', textDecoration: 'underline' }}
                        onClick={() => navigate(`/inventory/adjustments/${a.id}`)}>{a.number}</span>
                    </td>
                    <td>{a.warehouse?.name || '—'}</td>
                    <td><Badge variant="info">{typeMap[a.type] || a.type}</Badge></td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>{(a as any).created_by_profile?.full_name || '—'}</td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{formatDateShort(a.created_at)}</td>
                    <td><Badge variant={statusMap[a.status]?.variant || 'neutral'}>{statusMap[a.status]?.label || a.status}</Badge></td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', maxWidth: 200, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                      {a.status === 'rejected' && (a as any).rejection_reason ? <span style={{ color: 'var(--color-danger)' }}>{(a as any).rejection_reason}</span> : (a.reason || '—')}
                    </td>
                    <td>
                      {a.status === 'pending' && can('inventory.update') && (
                        <div className="flex gap-1">
                          <Button variant="success" size="sm" title="اعتماد" onClick={() => setConfirmTarget({ adj: a, action: 'approve' })}>
                            <Check size={12} />
                          </Button>
                          <Button variant="danger" size="sm" title="رفض" onClick={() => { setRejectReason(''); setRejectModal(a) }}>
                            <XIcon size={12} />
                          </Button>
                        </div>
                      )}
                    </td>
                  </tr>
                  {/* Expanded items */}
                  {expandedId === a.id && a.items && a.items.length > 0 && (
                    <tr>
                      <td colSpan={9} style={{ padding: 'var(--space-3) var(--space-6)', background: 'var(--bg-secondary)' }}>
                        <table style={{ width: '100%', fontSize: 'var(--text-xs)' }}>
                          <thead><tr><th>المنتج</th><th>كمية النظام</th><th>الكمية الفعلية</th><th>الفرق</th>{canViewCosts && <th>تكلفة الوحدة</th>}<th>ملاحظات</th></tr></thead>
                          <tbody>
                            {a.items.map((it: any) => (
                              <tr key={it.id}>
                                <td>{it.product?.name || it.product_id}</td>
                                <td>{formatNumber(it.system_qty)}</td>
                                <td>{formatNumber(it.actual_qty)}</td>
                                <td style={{
                                  fontWeight: 700,
                                  color: it.difference > 0 ? 'var(--color-success)' : it.difference < 0 ? 'var(--color-danger)' : 'var(--text-primary)'
                                }}>
                                  {it.difference > 0 ? `+${formatNumber(it.difference)}` : formatNumber(it.difference)}
                                </td>
                                {canViewCosts && <td>{it.unit_cost ? formatNumber(it.unit_cost) : '—'}</td>}
                                <td>{it.notes || '—'}</td>
                              </tr>
                            ))}
                          </tbody>
                        </table>
                      </td>
                    </tr>
                  )}
                </Fragment>
              ))}
            </tbody>
          </table>
        )}

        {totalPages > 1 && (
          <div className="pagination" style={{ padding: 'var(--space-4)' }}>
            <span className="pagination-info">صفحة {page} من {totalPages}</span>
            <div className="pagination-buttons">
              <button className="pagination-btn" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>‹</button>
              <button className="pagination-btn" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>›</button>
            </div>
          </div>
        )}
      </div>

      {/* Create Modal */}
      <Modal open={createModal} onClose={() => setCreateModal(false)} title="تسوية جديدة" size="lg" disableOverlayClose
        footer={
          <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
            <Button variant="secondary" onClick={() => setCreateModal(false)}>إلغاء</Button>
            <Button onClick={handleCreate} loading={createSaving}>إنشاء التسوية</Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          <div className="grid grid-3 gap-4">
            <div className="form-group">
              <label className="form-label required">المخزن</label>
              <select className="form-select" value={createForm.warehouse_id} onChange={e => handleWarehouseChange(e.target.value)}>
                <option value="">اختر</option>
                {(isAdmin ? warehouses : myWarehouses).filter(w => w.is_active).map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label">النوع</label>
              <select className="form-select" value={createForm.type} onChange={e => handleTypeChange(e.target.value as AdjustmentType)}>
                <option value="count">📋 جرد (مقارنة)</option>
                <option value="add">➕ إضافة مخزون</option>
                <option value="remove">➖ إزالة مخزون</option>
              </select>
              <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-1)', display: 'block' }}>
                {typeDescriptions[createForm.type]}
              </span>
            </div>
            <div className="form-group">
              <label className="form-label">السبب</label>
              <input className="form-input" value={createForm.reason} onChange={e => setCreateForm(f => ({ ...f, reason: e.target.value }))} />
            </div>
          </div>

          <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
            بنود التسوية
            {createForm.type !== 'count' && (
              <Badge variant={createForm.type === 'add' ? 'success' : 'danger'}>
                {createForm.type === 'add' ? 'إضافة' : 'إزالة'}
              </Badge>
            )}
          </h3>
          {createItems.map((item, idx) => (
            <div key={idx} style={{ display: 'flex', gap: 'var(--space-3)', alignItems: 'end', flexWrap: 'wrap',
              padding: 'var(--space-3)', borderRadius: 'var(--radius-md)',
              background: idx % 2 === 0 ? 'transparent' : 'var(--bg-secondary)' }}>
              
              {/* المنتج */}
              <div className="form-group" style={{ flex: 2, minWidth: 160 }}>
                <label className="form-label">المنتج</label>
                <select className="form-select" value={item.product_id} onChange={e => handleProductChange(idx, e.target.value)}>
                  <option value="">اختر</option>
                  {products.map(p => <option key={p.id} value={p.id}>{p.name}</option>)}
                </select>
              </div>

              {/* كمية النظام — دائماً معروضة */}
              <div className="form-group" style={{ flex: 0.8, minWidth: 80 }}>
                <label className="form-label">كمية النظام</label>
                <input type="number" className="form-input" dir="ltr" value={item.system_qty} disabled
                  style={{ background: 'var(--bg-secondary)', fontWeight: 600 }} />
              </div>

              {/* حقل الإدخال الرئيسي — يتغير حسب النوع */}
              {createForm.type === 'count' ? (
                <div className="form-group" style={{ flex: 0.8, minWidth: 80 }}>
                  <label className="form-label">الكمية الفعلية</label>
                  <input type="number" className="form-input" dir="ltr" min={0}
                    value={item.actual_qty} onChange={e => updateItem(idx, 'actual_qty', +e.target.value)} />
                </div>
              ) : (
                <div className="form-group" style={{ flex: 0.8, minWidth: 80 }}>
                  <label className="form-label" style={{ color: createForm.type === 'add' ? 'var(--color-success)' : 'var(--color-danger)' }}>
                    {createForm.type === 'add' ? 'كمية الإضافة' : 'كمية الإزالة'}
                  </label>
                  <input type="number" className="form-input" dir="ltr" min={0}
                    max={createForm.type === 'remove' ? item.system_qty : undefined}
                    value={item.qty_change || ''}
                    onChange={e => updateItem(idx, 'qty_change', +e.target.value)}
                    style={{ borderColor: createForm.type === 'add' ? 'var(--color-success)' : 'var(--color-danger)' }} />
                </div>
              )}

              {/* مؤشر الفرق / النتيجة */}
              <div style={{ flex: 0.6, minWidth: 70, marginBottom: 'var(--space-1)', textAlign: 'center' }}>
                {item.product_id && (() => {
                  let diff = 0, resultQty = item.system_qty
                  if (createForm.type === 'count') {
                    diff = item.actual_qty - item.system_qty
                    resultQty = item.actual_qty
                  } else if (createForm.type === 'add') {
                    diff = item.qty_change
                    resultQty = item.system_qty + item.qty_change
                  } else {
                    diff = -item.qty_change
                    resultQty = Math.max(item.system_qty - item.qty_change, 0)
                  }
                  return (
                    <div style={{ display: 'flex', flexDirection: 'column', gap: '2px' }}>
                      <span style={{
                        fontSize: 'var(--text-xs)', fontWeight: 700,
                        color: diff > 0 ? 'var(--color-success)' : diff < 0 ? 'var(--color-danger)' : 'var(--text-muted)'
                      }}>
                        {diff > 0 ? `+${diff}` : diff === 0 ? '—' : diff}
                      </span>
                      {createForm.type !== 'count' && item.qty_change > 0 && (
                        <span style={{ fontSize: '10px', color: 'var(--text-muted)' }}>
                          → {resultQty}
                        </span>
                      )}
                    </div>
                  )
                })()}
              </div>

              {canViewCosts && (
                <div className="form-group" style={{ flex: 0.7, minWidth: 80 }}>
                  <label className="form-label">تكلفة الوحدة</label>
                  <input type="number" className="form-input" dir="ltr" min={0} step={0.01} value={item.unit_cost} onChange={e => updateItem(idx, 'unit_cost', +e.target.value)} />
                </div>
              )}
              <div className="form-group" style={{ flex: 1, minWidth: 100 }}>
                <label className="form-label">ملاحظات</label>
                <input className="form-input" value={item.notes} onChange={e => updateItem(idx, 'notes', e.target.value)} />
              </div>
              <Button variant="danger" size="sm" style={{ marginBottom: 'var(--space-1)' }} disabled={createItems.length <= 1} onClick={() => removeItem(idx)}>✕</Button>
            </div>
          ))}
          <Button variant="secondary" size="sm" onClick={addItem} style={{ alignSelf: 'flex-start' }}>
            <Plus size={14} /> بند إضافي
          </Button>
        </div>
      </Modal>

      {/* Approve Confirm Dialog — with impact summary */}
      {confirmTarget && confirmTarget.action === 'approve' && (() => {
        const impact = getImpactSummary(confirmTarget.adj)
        return (
          <ConfirmDialog
            open={true}
            title="اعتماد التسوية"
            message={`سيتم تطبيق فروق التسوية ${confirmTarget.adj.number} على المخزون.${impact ? `\n\n📦 ${impact.count} بند${impact.increases > 0 ? ` | ⬆ زيادة: ${impact.increases}` : ''}${impact.decreases > 0 ? ` | ⬇ نقص: ${impact.decreases}` : ''}` : ''}\n\nملاحظة: سيتم إعادة حساب الفروق مع المخزون الحالي لحظة الاعتماد.`}
            variant="info"
            confirmText="اعتماد"
            loading={actionLoading}
            onConfirm={executeAction}
            onCancel={() => setConfirmTarget(null)}
          />
        )
      })()}

      {/* Reject Modal — with reason input */}
      {rejectModal && (
        <Modal open={true} onClose={() => setRejectModal(null)} title="رفض التسوية" size="sm"
          footer={
            <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
              <Button variant="secondary" onClick={() => setRejectModal(null)}>إلغاء</Button>
              <Button variant="danger" loading={actionLoading} onClick={executeReject}>رفض التسوية</Button>
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
            سيتم رفض التسوية {rejectModal.number} بدون تطبيق أي تغييرات على المخزون.
          </p>
        </Modal>
      )}
    </div>
  )
}
