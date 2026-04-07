import { useState, Fragment, useMemo, useRef, useEffect, useCallback } from 'react'
import { useNavigate } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowLeftRight, Plus, ChevronDown, ChevronUp,
  Truck, PackageCheck, X as XIcon, Send, Download, Search, Warehouse as WarehouseIcon
} from 'lucide-react'
import {
  createTransfer, shipTransfer,
  approveAndShipTransfer, receiveTransfer, cancelTransfer,
  getAvailableStock, getMyWarehouses
} from '@/lib/services/inventory'
import { getProducts, getProductUnits } from '@/lib/services/products'
import { useTransfers, useWarehouses, useInvalidate } from '@/hooks/useQueryHooks'
import { useQuery } from '@tanstack/react-query'
import { useAuthStore } from '@/stores/auth-store'
import type { StockTransfer, Warehouse, TransferStatus } from '@/lib/types/master-data'
import { formatNumber, formatCurrency, formatDateShort } from '@/lib/utils/format'
import PageHeader from '@/components/shared/PageHeader'
import Badge from '@/components/ui/Badge'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import ConfirmDialog from '@/components/ui/ConfirmDialog'

// ─── Inline Product Search Combobox ───
function ProductSearchCombo({ value, productName, onSelect, onClear, disabled }: {
  value: string; productName: string;
  onSelect: (p: { id: string; name: string; sku: string }) => void;
  onClear: () => void; disabled?: boolean;
}) {
  const [q, setQ] = useState('')
  const [open, setOpen] = useState(false)
  const [results, setResults] = useState<{ id: string; name: string; sku: string }[]>([])
  const [searching, setSearching] = useState(false)
  const ref = useRef<HTMLDivElement>(null)
  const timer = useRef<ReturnType<typeof setTimeout>>()

  useEffect(() => {
    const handler = (e: MouseEvent) => {
      if (ref.current && !ref.current.contains(e.target as Node)) setOpen(false)
    }
    document.addEventListener('mousedown', handler)
    return () => document.removeEventListener('mousedown', handler)
  }, [])

  const doSearch = useCallback(async (term: string) => {
    if (term.length < 1) { setResults([]); return }
    setSearching(true)
    try {
      const res = await getProducts({ search: term, pageSize: 15, isActive: true })
      setResults(res.data.map(p => ({ id: p.id, name: p.name, sku: p.sku })))
    } catch { setResults([]) }
    finally { setSearching(false) }
  }, [])

  const handleInput = (v: string) => {
    setQ(v)
    setOpen(v.length > 0)
    if (timer.current) clearTimeout(timer.current)
    timer.current = setTimeout(() => doSearch(v), 250)
  }

  // Selected state
  if (value && productName) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', gap: 8,
        padding: '6px 10px', minHeight: 38,
        background: 'var(--color-primary-light, rgba(37,99,235,0.07))',
        border: '1.5px solid var(--color-primary)',
        borderRadius: 8,
      }}>
        <span style={{ flex: 1, fontWeight: 600, fontSize: 'var(--text-sm)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
          {productName}
        </span>
        <button type="button" onClick={onClear} style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--text-muted)', padding: 2, display: 'flex' }}>
          <XIcon size={14} />
        </button>
      </div>
    )
  }

  return (
    <div ref={ref} style={{ position: 'relative' }}>
      <div style={{ position: 'relative' }}>
        <Search size={14} style={{ position: 'absolute', right: 10, top: '50%', transform: 'translateY(-50%)', color: 'var(--text-muted)', pointerEvents: 'none' }} />
        <input
          className="form-input"
          style={{ paddingRight: 32 }}
          placeholder="ابحث عن منتج..."
          value={q}
          onChange={e => handleInput(e.target.value)}
          onFocus={() => { if (q.length > 0) setOpen(true) }}
          autoComplete="off"
          disabled={disabled}
        />
      </div>
      {open && results.length > 0 && (
        <div style={{
          position: 'absolute', zIndex: 999, top: 'calc(100% + 4px)',
          left: 0, right: 0,
          background: 'var(--bg-surface)',
          border: '1px solid var(--border-color)',
          borderRadius: 10,
          boxShadow: '0 12px 40px rgba(0,0,0,0.15)',
          maxHeight: 240, overflowY: 'auto',
        }}>
          {results.map((p, i) => (
            <div
              key={p.id}
              onMouseDown={e => { e.preventDefault(); onSelect(p); setQ(''); setOpen(false) }}
              style={{
                padding: '8px 12px', cursor: 'pointer',
                borderBottom: i < results.length - 1 ? '1px solid var(--border-color)' : 'none',
              }}
              onMouseEnter={e => (e.currentTarget.style.background = 'var(--bg-hover)')}
              onMouseLeave={e => (e.currentTarget.style.background = '')}
            >
              <div style={{ fontWeight: 600, fontSize: 'var(--text-sm)' }}>{p.name}</div>
              <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', fontFamily: 'monospace' }}>{p.sku}</div>
            </div>
          ))}
        </div>
      )}
      {open && q.length > 0 && results.length === 0 && !searching && (
        <div style={{
          position: 'absolute', zIndex: 999, top: 'calc(100% + 4px)',
          left: 0, right: 0, padding: '12px 16px', textAlign: 'center',
          background: 'var(--bg-surface)', border: '1px solid var(--border-color)',
          borderRadius: 10, fontSize: 'var(--text-sm)', color: 'var(--text-muted)',
        }}>
          لا توجد نتائج
        </div>
      )}
    </div>
  )
}

export default function TransfersPage() {
  const can = useAuthStore(s => s.can)
  const navigate = useNavigate()
  const invalidate = useInvalidate()
  const [statusFilter, setStatusFilter] = useState('')
  const [page, setPage] = useState(1)
  const [expandedId, setExpandedId] = useState<string | null>(null)
  const isAdmin = can('inventory.read_all')
  const canViewCosts = can('finance.view_costs')

  // React Query — cached & shared
  const { data: warehouses = [] } = useWarehouses()
  const { data: myWarehousesData = [], isLoading: myWhLoading } = useQuery({
    queryKey: ['my-warehouses'],
    queryFn: () => getMyWarehouses(),
    staleTime: 5 * 60 * 1000,
    // نجلب دائماً — حتى لو كان المستخدم أدمن 
    // لأن الأدمن قد يملك مخزناً شخصياً ويجب تعيينه افتراضياً
  })
  const myWarehouses = myWarehousesData as Warehouse[]

  const queryParams = useMemo(() => ({
    status: (statusFilter || undefined) as TransferStatus | undefined,
    page, pageSize: 25,
  }), [statusFilter, page])

  const { data: result, isLoading: loading } = useTransfers(queryParams)
  const transfers = result?.data ?? []
  const totalPages = result?.totalPages ?? 1
  const totalCount = result?.count ?? 0

  // Create modal
  const [createModal, setCreateModal] = useState(false)
  const [direction, setDirection] = useState<'push' | 'pull'>('push')
  const [createForm, setCreateForm] = useState({ from_warehouse_id: '', to_warehouse_id: '', notes: '' })
  const [createItems, setCreateItems] = useState<{
    product_id: string; unit_id: string; quantity: number; available: number | null
  }[]>([])
  const [productNames, setProductNames] = useState<Record<string, string>>({})
  const [productUnitsMap, setProductUnitsMap] = useState<Record<string, { id: string; name: string; symbol: string }[]>>({})
  const [createSaving, setCreateSaving] = useState(false)

  // Confirm dialogs
  const [confirmAction, setConfirmAction] = useState<{
    transfer: StockTransfer; action: 'ship' | 'approve_ship' | 'receive' | 'cancel'
  } | null>(null)
  const [actionLoading, setActionLoading] = useState(false)


  // ─── Create Modal Helpers ───
  // تعيين المخزن الافتراضي: الأول من مخازن المستخدم
  const myWhId = myWarehouses.length > 0 ? myWarehouses[0].id : ''
  // قفل فقط إذا كان غير أدمن + مخزن واحد — أدمن بمخزن شخصي يحصل على افتراضي لكن يظل الحقل قابل للتغيير
  const myWhLocked = !isAdmin && myWarehouses.length === 1

  const openCreate = async () => {
    const defaultDir: 'push' | 'pull' = 'push'

    // تعيين ذكي: نقرأ مخازن المستخدم — من cache أو من الخادم مباشرة إن لزم
    let resolvedMyWh = myWarehouses
    if (resolvedMyWh.length === 0) {
      try { resolvedMyWh = await getMyWarehouses() } catch { resolvedMyWh = [] }
    }
    // الافتراضي يعتمد على myWarehouses فقط — بغض النظر عن صلاحية الأدمن
    const defaultId = resolvedMyWh.length > 0 ? resolvedMyWh[0].id : ''

    // Push: from = مخزني, Pull: to = مخزني
    setCreateForm({
      from_warehouse_id: defaultId,
      to_warehouse_id: '',
      notes: '',
    })
    setCreateItems([{ product_id: '', unit_id: '', quantity: 1, available: null }])
    setDirection(defaultDir)
    setProductNames({})
    setCreateModal(true)
  }

  // عند تغيير الاتجاه: إعادة تعيين المخازن
  const handleDirectionChange = (newDir: 'push' | 'pull') => {
    setDirection(newDir)
    if (myWhId) {
      if (newDir === 'push') {
        setCreateForm(f => ({ ...f, from_warehouse_id: myWhId, to_warehouse_id: f.to_warehouse_id === myWhId ? '' : f.to_warehouse_id }))
      } else {
        setCreateForm(f => ({ ...f, to_warehouse_id: myWhId, from_warehouse_id: f.from_warehouse_id === myWhId ? '' : f.from_warehouse_id }))
      }
    }
  }

  const addItem = () => setCreateItems(i => [...i, { product_id: '', unit_id: '', quantity: 1, available: null }])
  const removeItem = (idx: number) => setCreateItems(i => i.filter((_, j) => j !== idx))
  const updateItem = (idx: number, key: string, val: any) =>
    setCreateItems(items => items.map((item, j) => j === idx ? { ...item, [key]: val } : item))

  // عند اختيار منتج: جلب الوحدات + الكمية المتاحة
  const handleProductSelect = async (idx: number, product: { id: string; name: string; sku: string }) => {
    const productId = product.id
    const sourceWh = createForm.from_warehouse_id
    setCreateItems(items => items.map((item, j) => j === idx ? { ...item, product_id: productId, unit_id: '', available: null } : item))
    setProductNames(m => ({ ...m, [productId]: product.name }))

    // جلب الوحدات
    if (!productUnitsMap[productId]) {
      try {
        const pUnits = await getProductUnits(productId)
        // جلب المنتج لمعرفة الوحدة الأساسية
        const { getProduct } = await import('@/lib/services/products')
        const fullProduct = await getProduct(productId)
        const unitsList: { id: string; name: string; symbol: string }[] = []
        if (fullProduct?.base_unit) unitsList.push({ id: fullProduct.base_unit.id, name: fullProduct.base_unit.name, symbol: fullProduct.base_unit.symbol })
        pUnits.forEach(pu => { if (pu.unit && !unitsList.some(u => u.id === pu.unit!.id)) unitsList.push({ id: pu.unit!.id, name: pu.unit!.name, symbol: pu.unit!.symbol }) })
        setProductUnitsMap(m => ({ ...m, [productId]: unitsList }))
      } catch { /* ignore */ }
    }

    // جلب الكمية المتاحة من المخزن المصدر
    if (sourceWh) {
      try {
        const avail = await getAvailableStock(sourceWh, productId)
        setCreateItems(items => items.map((item, j) => j === idx ? { ...item, available: avail } : item))
      } catch { /* ignore */ }
    }
  }

  const handleProductClear = (idx: number) => {
    setCreateItems(items => items.map((item, j) => j === idx ? { ...item, product_id: '', unit_id: '', available: null } : item))
  }

  // تحديث الكمية المتاحة عند تغيير المخزن المصدر
  const handleSourceWarehouseChange = async (whId: string) => {
    setCreateForm(f => ({ ...f, from_warehouse_id: whId }))
    // تحديث الكميات المتاحة لكل البنود
    if (whId) {
      const updatedItems = await Promise.all(
        createItems.map(async (item) => {
          if (item.product_id) {
            try {
              const avail = await getAvailableStock(whId, item.product_id)
              return { ...item, available: avail }
            } catch { return { ...item, available: 0 } }
          }
          return item
        })
      )
      setCreateItems(updatedItems)
    }
  }

  const handleCreate = async () => {
    if (!createForm.from_warehouse_id || !createForm.to_warehouse_id) { toast.error('يرجى اختيار المخزنين'); return }
    if (createForm.from_warehouse_id === createForm.to_warehouse_id) { toast.error('لا يمكن التحويل لنفس المخزن'); return }
    const validItems = createItems.filter(i => i.product_id && i.unit_id && i.quantity > 0)
    if (!validItems.length) { toast.error('يرجى إضافة بنود صالحة'); return }

    // فحص الكميات مقابل المتاح
    for (const item of validItems) {
      if (item.available !== null && item.quantity > item.available) {
        const pName = productNames[item.product_id] || ''
        toast.error(`الكمية المطلوبة من "${pName}" أكبر من المتاح (${item.available})`)
        return
      }
    }

    setCreateSaving(true)
    try {
      await createTransfer(
        { ...createForm, direction },
        validItems.map(({ product_id, unit_id, quantity }) => ({ product_id, unit_id, quantity }))
      )
      toast.success(direction === 'push' ? 'تم إنشاء التحويل وحجز الكميات' : 'تم إرسال طلب التحويل')
      setCreateModal(false)
      invalidate('transfers')
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setCreateSaving(false) }
  }

  // ─── Actions ───
  const executeAction = async () => {
    if (!confirmAction) return
    setActionLoading(true)
    try {
      switch (confirmAction.action) {
        case 'ship': await shipTransfer(confirmAction.transfer.id); break
        case 'approve_ship': await approveAndShipTransfer(confirmAction.transfer.id); break
        case 'receive': await receiveTransfer(confirmAction.transfer.id); break
        case 'cancel': await cancelTransfer(confirmAction.transfer.id); break
      }
      toast.success(
        confirmAction.action === 'ship' ? 'تم الشحن بنجاح' :
        confirmAction.action === 'approve_ship' ? 'تمت الموافقة والشحن' :
        confirmAction.action === 'receive' ? 'تم تأكيد الاستلام' : 'تم الإلغاء'
      )
      invalidate('transfers')
    } catch (e: any) { toast.error(e?.message || 'فشلت العملية') }
    finally { setActionLoading(false); setConfirmAction(null) }
  }

  const statusMap: Record<string, { label: string; variant: 'warning' | 'info' | 'primary' | 'success' | 'danger' }> = {
    pending: { label: 'معلق', variant: 'warning' },
    approved: { label: 'معتمد', variant: 'info' },
    in_transit: { label: 'قيد الشحن', variant: 'primary' },
    received: { label: 'مُستلم', variant: 'success' },
    cancelled: { label: 'ملغي', variant: 'danger' },
  }

  const directionLabel = (d: string) => d === 'push' ? 'إرسال' : 'طلب'

  const confirmConfig = confirmAction ? {
    ship: { title: 'تأكيد الشحن', message: `سيتم خصم المخزون من "${confirmAction.transfer.from_warehouse?.name}" وإرسال البنود. هل تريد المتابعة؟`, variant: 'info' as const, text: 'شحن' },
    approve_ship: { title: 'موافقة وشحن', message: `سيتم خصم المخزون من "${confirmAction.transfer.from_warehouse?.name}" وإرسال البنود للمخزن الطالب. هل تريد المتابعة؟`, variant: 'info' as const, text: 'موافقة وشحن' },
    receive: { title: 'تأكيد الاستلام', message: `سيتم إضافة البنود إلى مخزن "${confirmAction.transfer.to_warehouse?.name}". هل تريد تأكيد الاستلام؟`, variant: 'info' as const, text: 'تأكيد الاستلام' },
    cancel: { title: 'إلغاء التحويل', message: `سيتم إلغاء التحويل ${confirmAction.transfer.number}. هل تريد المتابعة؟`, variant: 'danger' as const, text: 'إلغاء' },
  }[confirmAction.action] : null

  return (
    <div className="page-container animate-enter">
      <PageHeader
        title="تحويلات المخزون"
        subtitle={loading ? '...' : `${totalCount} تحويل`}
        actions={can('inventory.transfers.create') ? (
          <Button icon={<Plus size={16} />} onClick={openCreate} className="desktop-only-btn">تحويل جديد</Button>
        ) : undefined}
      />

      {/* Filters */}
      <div className="edara-card" style={{ padding: 'var(--space-4)', marginBottom: 'var(--space-4)' }}>
        <select className="form-select" style={{ width: 160 }} value={statusFilter}
          onChange={e => { setStatusFilter(e.target.value); setPage(1) }}>
          <option value="">كل الحالات</option>
          {Object.entries(statusMap).map(([k, v]) => <option key={k} value={k}>{v.label}</option>)}
        </select>
      </div>

      {/* ── DESKTOP: transfers table ─────────────────────────── */}
      <div className="tr-table-view edara-card" style={{ overflow: 'auto' }}>
        {loading ? (
          <div style={{ padding: 'var(--space-6)' }}>
            {[1,2,3,4,5].map(i => <div key={i} className="skeleton skeleton-row" />)}
          </div>
        ) : transfers.length === 0 ? (
          <div className="empty-state" style={{ padding: 'var(--space-8)' }}>
            <ArrowLeftRight size={48} className="empty-state-icon" />
            <p className="empty-state-title">لا يوجد تحويلات</p>
            <p className="empty-state-text">أنشئ تحويل جديد لنقل البضائع بين المخازن</p>
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th style={{ width: 30 }}></th>
                <th>الرقم</th>
                <th>النوع</th>
                <th>من</th>
                <th>إلى</th>
                <th className="hide-mobile">التاريخ</th>
                <th>الحالة</th>
                <th style={{ width: 200 }}>إجراءات</th>
              </tr>
            </thead>
            <tbody>
              {transfers.map(t => (
                <Fragment key={t.id}>
                  <tr>
                    <td>
                      <Button variant="ghost" size="sm" onClick={() => setExpandedId(expandedId === t.id ? null : t.id)}>
                        {expandedId === t.id ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                      </Button>
                    </td>
                    <td>
                      <span dir="ltr" style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', color: 'var(--color-primary)', cursor: 'pointer', textDecoration: 'underline' }}
                        onClick={() => navigate(`/inventory/transfers/${t.id}`)}>{t.number}</span>
                    </td>
                    <td>
                      <Badge variant={t.direction === 'push' ? 'primary' : 'info'}>
                        {t.direction === 'push' ? <><Send size={10} /> إرسال</> : <><Download size={10} /> طلب</>}
                      </Badge>
                    </td>
                    <td>{t.from_warehouse?.name || '—'}</td>
                    <td>{t.to_warehouse?.name || '—'}</td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{formatDateShort(t.created_at)}</td>
                    <td><Badge variant={statusMap[t.status]?.variant || 'neutral'}>{statusMap[t.status]?.label || t.status}</Badge></td>
                    <td>
                      {(() => {
                        const myWhIds = new Set(myWarehouses.map(w => w.id))
                        const userId = useAuthStore.getState().profile?.id
                        const iManageSource = isAdmin || myWhIds.has(t.from_warehouse_id)
                        const iManageDest = isAdmin || myWhIds.has(t.to_warehouse_id)
                        const iAmCreator = isAdmin || t.requested_by === userId
                        return (
                          <div className="flex gap-1" style={{ flexWrap: 'wrap' }}>
                            {t.status === 'pending' && t.direction === 'push' && iManageSource && (
                              <Button variant="primary" size="sm" onClick={() => setConfirmAction({ transfer: t, action: 'ship' })}><Truck size={12} /> شحن</Button>
                            )}
                            {t.status === 'pending' && t.direction === 'pull' && iManageSource && (
                              <Button variant="primary" size="sm" onClick={() => setConfirmAction({ transfer: t, action: 'approve_ship' })}><Truck size={12} /> موافقة وشحن</Button>
                            )}
                            {t.status === 'in_transit' && iManageDest && t.approved_by !== userId && (
                              <Button variant="success" size="sm" onClick={() => setConfirmAction({ transfer: t, action: 'receive' })}><PackageCheck size={12} /> استلام</Button>
                            )}
                            {t.status === 'pending' && iAmCreator && (
                              <Button variant="danger" size="sm" onClick={() => setConfirmAction({ transfer: t, action: 'cancel' })}><XIcon size={12} /></Button>
                            )}
                            {t.status === 'in_transit' && iManageSource && (
                              <Button variant="danger" size="sm" onClick={() => setConfirmAction({ transfer: t, action: 'cancel' })}><XIcon size={12} /></Button>
                            )}
                          </div>
                        )
                      })()}
                    </td>
                  </tr>
                  {expandedId === t.id && t.items && t.items.length > 0 && (
                    <tr>
                      <td colSpan={8} style={{ padding: 'var(--space-3) var(--space-6)', background: 'var(--bg-secondary)' }}>
                        <table style={{ width: '100%', fontSize: 'var(--text-xs)' }}>
                          <thead><tr><th>المنتج</th><th>الوحدة</th><th>الكمية</th><th>الكمية المستلمة</th>{canViewCosts && <th>تكلفة الوحدة</th>}</tr></thead>
                          <tbody>
                            {t.items.map((it: any) => (
                              <tr key={it.id}>
                                <td>{it.product?.name || it.product_id}</td>
                                <td>{it.unit?.symbol || it.unit_id}</td>
                                <td>{formatNumber(it.quantity)}</td>
                                <td>{it.received_quantity ? formatNumber(it.received_quantity) : '—'}</td>
                                {canViewCosts && <td>{it.unit_cost ? formatCurrency(it.unit_cost) : '—'}</td>}
                              </tr>
                            ))}
                          </tbody>
                        </table>
                        {t.notes && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 'var(--space-2)' }}>ملاحظات: {t.notes}</p>}
                        {t.sent_at && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>تاريخ الشحن: {formatDateShort(t.sent_at)}</p>}
                        {t.received_at && <p style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>تاريخ الاستلام: {formatDateShort(t.received_at)}</p>}
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

      {/* ── MOBILE: Transfer Card List ───────────────────────────── */}
      <div className="tr-card-view">
        {loading ? (
          <div className="mobile-card-list">
            {[1,2,3].map(i => <div key={i} className="edara-card" style={{ height: 104 }}><div className="skeleton" style={{ height: '100%' }} /></div>)}
          </div>
        ) : transfers.length === 0 ? (
          <div className="edara-card" style={{ padding: 'var(--space-8)', textAlign: 'center', color: 'var(--text-muted)' }}>
            <ArrowLeftRight size={40} style={{ margin: '0 auto 12px', display: 'block', opacity: 0.3 }} />
            <p>لا يوجد تحويلات</p>
          </div>
        ) : (
          <div className="mobile-card-list">
            {transfers.map((t: StockTransfer) => {
              const st = statusMap[t.status]
              const myWhIds = new Set(myWarehouses.map(w => w.id))
              const userId = useAuthStore.getState().profile?.id
              const iManageSource = isAdmin || myWhIds.has(t.from_warehouse_id)
              const iManageDest   = isAdmin || myWhIds.has(t.to_warehouse_id)
              const iAmCreator    = isAdmin || t.requested_by === userId
              return (
                <div key={t.id} className="edara-card tr-mobile-card" onClick={() => navigate(`/inventory/transfers/${t.id}`)}>
                  <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start', marginBottom: 8 }}>
                    <div>
                      <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                        <span style={{ fontFamily: 'monospace', fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--color-primary)' }} dir="ltr">{t.number}</span>
                        <Badge variant={t.direction === 'push' ? 'primary' : 'info'}>
                          {t.direction === 'push' ? <><Send size={9} /> إرسال</> : <><Download size={9} /> طلب</>}
                        </Badge>
                      </div>
                      <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 3 }}>{formatDateShort(t.created_at)}</div>
                    </div>
                    <Badge variant={st?.variant || 'neutral'}>{st?.label || t.status}</Badge>
                  </div>
                  <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 8 }}>
                    <WarehouseIcon size={11} />
                    <span>{t.from_warehouse?.name || '—'}</span>
                    <ArrowLeftRight size={10} style={{ color: 'var(--color-primary)', flexShrink: 0 }} />
                    <span>{t.to_warehouse?.name || '—'}</span>
                  </div>
                  {/* Action buttons inline in card */}
                  <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }} onClick={e => e.stopPropagation()}>
                    {t.status === 'pending' && t.direction === 'push' && iManageSource && (
                      <Button variant="primary" size="sm" icon={<Truck size={12} />}
                        onClick={() => setConfirmAction({ transfer: t, action: 'ship' })}>شحن</Button>
                    )}
                    {t.status === 'pending' && t.direction === 'pull' && iManageSource && (
                      <Button variant="primary" size="sm" icon={<Truck size={12} />}
                        onClick={() => setConfirmAction({ transfer: t, action: 'approve_ship' })}>موافقة وشحن</Button>
                    )}
                    {t.status === 'in_transit' && iManageDest && t.approved_by !== userId && (
                      <Button variant="success" size="sm" icon={<PackageCheck size={12} />}
                        onClick={() => setConfirmAction({ transfer: t, action: 'receive' })}>استلام</Button>
                    )}
                    {(t.status === 'pending' && iAmCreator) && (
                      <Button variant="danger" size="sm" icon={<XIcon size={12} />}
                        onClick={() => setConfirmAction({ transfer: t, action: 'cancel' })}>إلغاء</Button>
                    )}
                    {t.status === 'in_transit' && iManageSource && (
                      <Button variant="danger" size="sm" icon={<XIcon size={12} />}
                        onClick={() => setConfirmAction({ transfer: t, action: 'cancel' })}>إلغاء</Button>
                    )}
                  </div>
                </div>
              )
            })}
          </div>
        )}
        {totalPages > 1 && (
          <div className="mobile-pagination">
            <Button variant="ghost" size="sm" disabled={page <= 1} onClick={() => setPage(p => p - 1)}>السابق</Button>
            <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{page} / {totalPages}</span>
            <Button variant="ghost" size="sm" disabled={page >= totalPages} onClick={() => setPage(p => p + 1)}>التالي</Button>
          </div>
        )}
      </div>

      {/* Mobile FAB */}
      {can('inventory.transfers.create') && (
        <button className="tr-fab" onClick={openCreate} aria-label="تحويل جديد">
          <Plus size={24} />
        </button>
      )}

      {/* Create Modal → ResponsiveModal (Bottom Sheet on mobile) */}
      <ResponsiveModal open={createModal} onClose={() => setCreateModal(false)} title="تحويل جديد"
        footer={
          <div className="flex gap-2 justify-end" style={{ width: '100%' }}>
            <Button variant="secondary" onClick={() => setCreateModal(false)}>إلغاء</Button>
            <Button onClick={handleCreate} loading={createSaving}>
              {direction === 'push' ? 'إنشاء وحجز الكميات' : 'إرسال الطلب'}
            </Button>
          </div>
        }
      >
        <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>
          {/* Direction selector */}
          <div className="form-group">
            <label className="form-label">نوع التحويل</label>
            <div className="flex gap-2">
              <Button
                variant={direction === 'push' ? 'primary' : 'secondary'} size="sm"
                onClick={() => handleDirectionChange('push')}
              ><Send size={14} /> إرسال بضاعة</Button>
              <Button
                variant={direction === 'pull' ? 'primary' : 'secondary'} size="sm"
                onClick={() => handleDirectionChange('pull')}
              ><Download size={14} /> طلب بضاعة</Button>
            </div>
          </div>

          <div className="grid grid-2 gap-4">
            <div className="form-group">
              <label className="form-label required">{direction === 'push' ? 'من مخزن (المُرسل)' : 'من مخزن (المصدر)'}</label>
              {/* Push + غير أدمن: مقفول على مخزني */}
              <select className="form-select" value={createForm.from_warehouse_id}
                onChange={e => handleSourceWarehouseChange(e.target.value)}
              disabled={myWhLocked && direction === 'push'}
                style={myWhLocked && direction === 'push' ? { background: 'var(--bg-secondary)', fontWeight: 600 } : {}}
              >
                <option value="">اختر</option>
                {(direction === 'push' && !isAdmin
                  ? myWarehouses
                  : warehouses.filter(w => w.is_active)
                ).map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
            </div>
            <div className="form-group">
              <label className="form-label required">{direction === 'push' ? 'إلى مخزن (المُستلم)' : 'إلى مخزن (مخزنك)'}</label>
              {/* Pull + غير أدمن: مقفول على مخزني */}
              <select className="form-select" value={createForm.to_warehouse_id}
                onChange={e => setCreateForm(f => ({ ...f, to_warehouse_id: e.target.value }))}
                disabled={myWhLocked && direction === 'pull'}
                style={myWhLocked && direction === 'pull' ? { background: 'var(--bg-secondary)', fontWeight: 600 } : {}}
              >
                <option value="">اختر</option>
                {(direction === 'pull' && !isAdmin
                  ? myWarehouses
                  : warehouses.filter(w => w.is_active && w.id !== createForm.from_warehouse_id)
                ).map(w => <option key={w.id} value={w.id}>{w.name}</option>)}
              </select>
            </div>
          </div>
          <div className="form-group">
            <label className="form-label">ملاحظات</label>
            <textarea className="form-textarea" rows={2} value={createForm.notes} onChange={e => setCreateForm(f => ({ ...f, notes: e.target.value }))} />
          </div>

          <h3 style={{ fontWeight: 700, fontSize: 'var(--text-sm)' }}>بنود التحويل</h3>
          {createItems.map((item, idx) => (
            <div key={idx} style={{ display: 'flex', gap: 'var(--space-3)', alignItems: 'end', flexWrap: 'wrap' }}>
              <div className="form-group" style={{ flex: 2, minWidth: 200 }}>
                <label className="form-label">المنتج</label>
                <ProductSearchCombo
                  value={item.product_id}
                  productName={productNames[item.product_id] || ''}
                  onSelect={p => handleProductSelect(idx, p)}
                  onClear={() => handleProductClear(idx)}
                />
              </div>
              <div className="form-group" style={{ flex: 1, minWidth: 100 }}>
                <label className="form-label">الوحدة</label>
                <select className="form-select" value={item.unit_id} onChange={e => updateItem(idx, 'unit_id', e.target.value)} disabled={!productUnitsMap[item.product_id]?.length}>
                  <option value="">اختر</option>
                  {(productUnitsMap[item.product_id] || []).map(u => <option key={u.id} value={u.id}>{u.name} ({u.symbol})</option>)}
                </select>
              </div>
              <div className="form-group" style={{ flex: 0.7, minWidth: 80 }}>
                <label className="form-label">الكمية</label>
                <input type="number" className="form-input" dir="ltr" min={1}
                  max={item.available !== null ? item.available : undefined}
                  value={item.quantity}
                  onChange={e => updateItem(idx, 'quantity', +e.target.value)}
                  style={item.available !== null && item.quantity > item.available ? { borderColor: 'var(--color-danger)' } : {}}
                />
              </div>
              <div style={{ flex: 0.5, minWidth: 70, marginBottom: 'var(--space-1)' }}>
                {item.available !== null && (
                  <span style={{
                    fontSize: 'var(--text-xs)',
                    color: item.quantity > item.available ? 'var(--color-danger)' : 'var(--color-success)',
                    fontWeight: 600
                  }}>
                    متاح: {formatNumber(item.available)}
                  </span>
                )}
              </div>
              <Button variant="danger" size="sm" style={{ marginBottom: 'var(--space-1)' }} disabled={createItems.length <= 1} onClick={() => removeItem(idx)}>✕</Button>
            </div>
          ))}
          <Button variant="secondary" size="sm" onClick={addItem} style={{ alignSelf: 'flex-start' }}>
            <Plus size={14} /> بند إضافي
          </Button>
        </div>
      </ResponsiveModal>

      {/* Confirm Dialog */}
      {confirmAction && confirmConfig && (
        <ConfirmDialog
          open={true}
          title={confirmConfig.title}
          message={confirmConfig.message}
          variant={confirmConfig.variant}
          confirmText={confirmConfig.text}
          loading={actionLoading}
          onConfirm={executeAction}
          onCancel={() => setConfirmAction(null)}
        />
      )}

      <style>{`
        .tr-table-view { display: block; }
        .tr-card-view  { display: none; }
        .tr-mobile-card { padding: var(--space-4); cursor: pointer; transition: background 0.12s; }
        .tr-mobile-card:hover { background: var(--bg-hover); }
        .mobile-card-list { display: flex; flex-direction: column; gap: var(--space-3); }
        .mobile-pagination { display: flex; align-items: center; justify-content: center; gap: var(--space-4); padding: var(--space-4) 0; }
        .tr-fab {
          position: fixed; bottom: calc(70px + var(--space-4)); left: var(--space-4);
          width: 56px; height: 56px; border-radius: 50%;
          background: var(--color-primary); color: #fff;
          border: none; cursor: pointer; display: flex; align-items: center; justify-content: center;
          box-shadow: 0 4px 20px rgba(37,99,235,0.35);
          z-index: var(--z-modal, 400); transition: transform 0.15s;
        }
        .tr-fab:hover { transform: scale(1.06); }
        @media (max-width: 768px) {
          .desktop-only-btn { display: none !important; }
          .tr-table-view { display: none; }
          .tr-card-view  { display: block; }
        }
        @media (min-width: 769px) { .tr-fab { display: none; } }
      `}</style>
    </div>
  )
}
