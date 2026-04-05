/**
 * SmartTransferDialog
 * ─────────────────────────────────────────────────────────────────────────
 * نافذة "التحويل الذكي" — تتيح للمندوب اختيار مسوداته وإنشاء طلب تحويل
 * مجمّع بكل المنتجات الناقصة من مخزنه باتجاه مخزن مصدر يختاره.
 *
 * تدفق UX:
 *   خطوة 1 — عرض المسودات + اختيار المطلوب منها
 *   خطوة 2 — ملخص المنتجات الناقصة + اختيار المخزن المصدر
 *   خطوة 3 — تأكيد + إنشاء طلب التحويل (Pull)
 * ─────────────────────────────────────────────────────────────────────────
 */

import { useState, useEffect, useMemo, useCallback, useRef } from 'react'
import {
  X, ArrowLeft, ArrowRight, Zap, Package, Warehouse,
  CheckCircle2, Loader2, ChevronDown, ChevronUp,
  AlertTriangle, Info, ShoppingCart,
} from 'lucide-react'
import { supabase } from '@/lib/supabase/client'
import { useAuthStore } from '@/stores/auth-store'
import { getWarehouses, getMyWarehouses, createTransfer } from '@/lib/services/inventory'
import { getSalesOrders } from '@/lib/services/sales'
import { formatNumber } from '@/lib/utils/format'
import { toast } from 'sonner'
import type { SalesOrder, Warehouse as WarehouseType } from '@/lib/types/master-data'

// ── Types ──────────────────────────────────────────────────────────────────

interface ProductNeed {
  product_id: string
  product_name: string
  product_sku: string
  unit_id: string
  unit_name: string
  unit_symbol: string
  total_qty: number       // الكمية المطلوبة من كل المسودات
  available_qty: number   // المتاح في مخزن المندوب
  needed_qty: number      // = total_qty - available_qty  (>0 يعني نقص)
  from_orders: string[]   // أرقام الطلبات المصدر
}

// ── Main Component ─────────────────────────────────────────────────────────

interface SmartTransferDialogProps {
  open: boolean
  onClose: () => void
  onSuccess?: (transferId: string) => void
}

export default function SmartTransferDialog({ open, onClose, onSuccess }: SmartTransferDialogProps) {
  const profile = useAuthStore(s => s.profile)
  const userId = profile?.id

  // ── State المراحل ──────────────────────────────────────────────────────
  const [step, setStep] = useState<1 | 2 | 3>(1)

  // الخطوة 1 — المسودات
  const [drafts, setDrafts] = useState<SalesOrder[]>([])
  const [loadingDrafts, setLoadingDrafts] = useState(false)
  const [selectedIds, setSelectedIds] = useState<Set<string>>(new Set())
  const [expandedId, setExpandedId] = useState<string | null>(null)

  // الخطوة 2 — تحليل النقص
  const [productNeeds, setProductNeeds] = useState<ProductNeed[]>([])
  const [myWarehouse, setMyWarehouse] = useState<WarehouseType | null>(null)
  const [allWarehouses, setAllWarehouses] = useState<WarehouseType[]>([])
  const [selectedSourceId, setSelectedSourceId] = useState<string>('')
  // وجهة التحويل — تُعيَّن تلقائياً من مخزن المستخدم، أو يختارها يدوياً إن لم يوجد
  const [selectedDestId, setSelectedDestId] = useState<string>('')
  const [analyzingStock, setAnalyzingStock] = useState(false)

  // الخطوة 3 — إنشاء التحويل
  const [creating, setCreating] = useState(false)

  const dialogRef = useRef<HTMLDialogElement>(null)

  // ── فتح/إغلاق الـ dialog ───────────────────────────────────────────────
  useEffect(() => {
    const el = dialogRef.current
    if (!el) return
    if (open) {
      el.showModal?.()
      // إعادة التهيئة عند كل فتح
      setStep(1)
      setSelectedIds(new Set())
      setExpandedId(null)
      setProductNeeds([])
      setSelectedSourceId('')
      setSelectedDestId('')
    } else {
      el.close?.()
    }
  }, [open])

  // إغلاق عند ضغط Escape
  useEffect(() => {
    const el = dialogRef.current
    if (!el) return
    const handler = (e: Event) => {
      e.preventDefault()
      onClose()
    }
    el.addEventListener('cancel', handler)
    return () => el.removeEventListener('cancel', handler)
  }, [onClose])

  // ── جلب المسودات ──────────────────────────────────────────────────────
  useEffect(() => {
    if (!open || !userId) return
    setLoadingDrafts(true)
    getSalesOrders({ status: 'draft', repId: userId, pageSize: 100 })
      .then(r => setDrafts(r.data))
      .catch(() => toast.error('تعذر جلب المسودات'))
      .finally(() => setLoadingDrafts(false))
  }, [open, userId])

  // ── جلب مخازن المستخدم ────────────────────────────────────────────────
  // المسودات لا تحمل warehouse_id — نجلب مخزن المستخدم المعيَّن له مسبقاً
  // كوجهة تلقائية للتحويل. إن لم يُوجد، يختار المستخدم يدوياً.
  useEffect(() => {
    if (!open) return
    Promise.all([getMyWarehouses(), getWarehouses({ isActive: true })])
      .then(([mine, all]) => {
        const firstMine = mine[0] ?? null
        setMyWarehouse(firstMine)
        setAllWarehouses(all)
        // تعيين الوجهة تلقائياً إذا وُجد مخزن للمستخدم
        if (firstMine) setSelectedDestId(firstMine.id)
      })
      .catch(() => {})
  }, [open])

  // ── تبديل اختيار المسودة ──────────────────────────────────────────────
  const toggleDraft = useCallback((id: string) => {
    setSelectedIds(prev => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }, [])

  const selectAll = useCallback(() => {
    setSelectedIds(new Set(drafts.map(d => d.id)))
  }, [drafts])

  const clearAll = useCallback(() => {
    setSelectedIds(new Set())
  }, [])

  // ── الانتقال لخطوة 2: تحليل المخزون ──────────────────────────────────
  const analyzeStock = useCallback(async () => {
    if (selectedIds.size === 0) return
    setAnalyzingStock(true)

    try {
      // 1. جمع بنود كل المسودات المختارة
      const chosenDrafts = drafts.filter(d => selectedIds.has(d.id))

      // المسودات قد لا تحتوي على items إذا لم تُجلب بالـ select الكامل
      // سنجلبها من الـ DB
      const { data: itemRows, error } = await supabase
        .from('sales_order_items')
        .select(`
          order_id,
          product_id,
          unit_id,
          base_quantity,
          product:products(id, name, sku),
          unit:units(id, name, symbol)
        `)
        .in('order_id', Array.from(selectedIds))

      if (error) throw error

      // 2. تجميع الكميات لكل منتج (دمج التكرار)
      const needMap = new Map<string, ProductNeed>()
      for (const row of (itemRows || []) as any[]) {
        const key = row.product_id + '_' + row.unit_id
        const orderNum = chosenDrafts.find(d => d.id === row.order_id)?.order_number ?? row.order_id
        if (needMap.has(key)) {
          const n = needMap.get(key)!
          n.total_qty += row.base_quantity
          if (!n.from_orders.includes(orderNum)) n.from_orders.push(orderNum)
        } else {
          needMap.set(key, {
            product_id: row.product_id,
            product_name: row.product?.name ?? '—',
            product_sku: row.product?.sku ?? '',
            unit_id: row.unit_id,
            unit_name: row.unit?.name ?? '',
            unit_symbol: row.unit?.symbol ?? '',
            total_qty: row.base_quantity,
            available_qty: 0,      // نُعبّئ لاحقاً
            needed_qty: 0,
            from_orders: [orderNum],
          })
        }
      }

      // 3. فحص المخزون المتاح في مخزن الوجهة (التلقائي أو المختار يدوياً)
      // ملاحظة: selectedDestId قد يكون فارغاً إذا لم يتم الاختيار بعد، نستخدم firstMine بديلاً
      const destIdForCheck = selectedDestId || myWarehouse?.id
      if (destIdForCheck) {
        const productIds = [...needMap.values()].map(n => n.product_id)
        const { data: stockRows } = await supabase
          .from('stock')
          .select('product_id, available_quantity')
          .eq('warehouse_id', destIdForCheck)
          .in('product_id', productIds)

        for (const s of (stockRows || []) as any[]) {
          for (const [, n] of needMap.entries()) {
            if (n.product_id === s.product_id) {
              n.available_qty = Math.max(0, s.available_quantity ?? 0)
              break
            }
          }
        }
      }

      // 4. حساب النقص
      const needs: ProductNeed[] = []
      for (const n of needMap.values()) {
        n.needed_qty = Math.max(0, n.total_qty - n.available_qty)
        needs.push(n)
      }

      // ترتيب: النقص أولاً
      needs.sort((a, b) => b.needed_qty - a.needed_qty)
      setProductNeeds(needs)
      setStep(2)
    } catch (e: any) {
      toast.error('تعذر تحليل المخزون: ' + (e.message ?? ''))
    } finally {
      setAnalyzingStock(false)
    }
  }, [selectedIds, drafts, myWarehouse])

  // ── المنتجات التي تحتاج تحويل فعلاً ──────────────────────────────────
  const shortageItems = useMemo(
    () => productNeeds.filter(n => n.needed_qty > 0),
    [productNeeds]
  )

  // ── المخازن المتاحة كمصدر (غير الوجهة المختارة) ──────────────────────
  const sourceWarehouses = useMemo(
    () => allWarehouses.filter(w => w.id !== selectedDestId),
    [allWarehouses, selectedDestId]
  )

  // ── مخزن الوجهة الفعلي (تلقائي أو يدوي) ──────────────────────────────
  const destWarehouse = useMemo(
    () => allWarehouses.find(w => w.id === selectedDestId) ?? myWarehouse,
    [allWarehouses, selectedDestId, myWarehouse]
  )

  // المخازن المتاحة كوجهة (لاختيار يدوي إذا لم يكن للمستخدم مخزن)
  const destWarehouses = useMemo(
    () => allWarehouses.filter(w => w.id !== selectedSourceId),
    [allWarehouses, selectedSourceId]
  )

  // ── إنشاء طلب التحويل ─────────────────────────────────────────────────
  const handleCreateTransfer = useCallback(async () => {
    if (!selectedSourceId || !destWarehouse || shortageItems.length === 0) return
    setCreating(true)

    try {
      const items = shortageItems.map(n => ({
        product_id: n.product_id,
        unit_id: n.unit_id,
        quantity: n.needed_qty,
      }))

      const transferId = await createTransfer(
        {
          from_warehouse_id: selectedSourceId,
          to_warehouse_id: destWarehouse.id,
          direction: 'pull',
          notes: `طلب تحويل ذكي — من ${selectedIds.size} مسودة: ${drafts
            .filter(d => selectedIds.has(d.id))
            .map(d => d.order_number)
            .join(', ')}`,
        },
        items
      )

      toast.success('تم إنشاء طلب التحويل بنجاح ✓')
      onSuccess?.(transferId)
      onClose()
    } catch (e: any) {
      toast.error('فشل إنشاء التحويل: ' + (e.message ?? ''))
    } finally {
      setCreating(false)
    }
  }, [selectedSourceId, destWarehouse, shortageItems, selectedIds, drafts, onSuccess, onClose])

  // ── Helpers ───────────────────────────────────────────────────────────
  const selectedDrafts = useMemo(() => drafts.filter(d => selectedIds.has(d.id)), [drafts, selectedIds])

  // ── Render ────────────────────────────────────────────────────────────
  if (!open) return null

  return (
    <dialog
      ref={dialogRef}
      id="smart-transfer-dialog"
      aria-labelledby="std-title"
      style={{
        padding: 0,
        border: 'none',
        borderRadius: 'var(--radius-2xl)',
        maxWidth: 680,
        width: '95vw',
        maxHeight: '92vh',
        overflow: 'hidden',
        background: 'var(--bg-surface)',
        boxShadow: 'var(--shadow-xl, 0 24px 48px rgba(0,0,0,.22))',
      }}
    >
      <div className="std-wrapper">
        {/* ─── Header ──────────────────────────────────────────────────── */}
        <div className="std-header">
          <div className="std-header-info">
            <div className="std-header-icon">
              <Zap size={20} />
            </div>
            <div>
              <h2 id="std-title" className="std-title">التحويل الذكي</h2>
              <p className="std-subtitle">
                {step === 1 && 'اختر المسودات التي تريد تجميعها'}
                {step === 2 && 'المنتجات الناقصة والمخزن المصدر'}
                {step === 3 && 'مراجعة وتأكيد طلب التحويل'}
              </p>
            </div>
          </div>
          <button className="std-close-btn" onClick={onClose} aria-label="إغلاق">
            <X size={18} />
          </button>
        </div>

        {/* ─── Stepper ─────────────────────────────────────────────────── */}
        <div className="std-stepper">
          {[
            { n: 1, label: 'المسودات' },
            { n: 2, label: 'التحليل' },
            { n: 3, label: 'التأكيد' },
          ].map(({ n, label }) => (
            <div key={n} className={`std-step ${step === n ? 'active' : step > n ? 'done' : ''}`}>
              <div className="std-step-dot">
                {step > n ? <CheckCircle2 size={14} /> : <span>{n}</span>}
              </div>
              <span className="std-step-label">{label}</span>
              {n < 3 && <div className="std-step-line" />}
            </div>
          ))}
        </div>

        {/* ─── Body ────────────────────────────────────────────────────── */}
        <div className="std-body">

          {/* ══ الخطوة 1: اختيار المسودات ══════════════════════════════ */}
          {step === 1 && (
            <div className="std-step-content animate-enter">
              {loadingDrafts ? (
                <div className="std-loading">
                  <Loader2 size={28} className="std-spin" />
                  <span>جاري تحميل المسودات...</span>
                </div>
              ) : drafts.length === 0 ? (
                <div className="std-empty">
                  <ShoppingCart size={40} style={{ color: 'var(--text-muted)' }} />
                  <p className="std-empty-title">لا توجد مسودات</p>
                  <p className="std-empty-sub">ليس لديك أوامر بيع في حالة مسودة حالياً</p>
                </div>
              ) : (
                <>
                  {/* شريط الإجراءات */}
                  <div className="std-action-bar">
                    <span className="std-count-badge">
                      {drafts.length} مسودة
                    </span>
                    <div style={{ display: 'flex', gap: 8 }}>
                      <button className="std-link-btn" onClick={selectAll}>تحديد الكل</button>
                      <button className="std-link-btn" onClick={clearAll}>إلغاء الكل</button>
                    </div>
                  </div>

                  {/* قائمة المسودات */}
                  <div className="std-draft-list">
                    {drafts.map(draft => {
                      const isSelected = selectedIds.has(draft.id)
                      const isExpanded = expandedId === draft.id
                      const itemCount = draft.items?.length ?? 0

                      return (
                        <div
                          key={draft.id}
                          className={`std-draft-card ${isSelected ? 'selected' : ''}`}
                        >
                          <div
                            className="std-draft-main"
                            onClick={() => toggleDraft(draft.id)}
                            role="checkbox"
                            aria-checked={isSelected}
                            tabIndex={0}
                            onKeyDown={e => e.key === ' ' && toggleDraft(draft.id)}
                          >
                            {/* Checkbox */}
                            <div className={`std-checkbox ${isSelected ? 'checked' : ''}`}>
                              {isSelected && <CheckCircle2 size={14} />}
                            </div>

                            {/* معلومات الطلب */}
                            <div className="std-draft-info">
                              <div className="std-draft-num" dir="ltr">{draft.order_number}</div>
                              <div className="std-draft-customer">{draft.customer?.name ?? '—'}</div>
                            </div>

                            {/* التاريخ والإجمالي */}
                            <div className="std-draft-meta">
                              <div className="std-draft-amount">
                                {formatNumber(draft.total_amount)} <span style={{ fontSize: '0.65rem', color: 'var(--text-muted)' }}>ج.م</span>
                              </div>
                              <div className="std-draft-date">
                                {new Date(draft.order_date).toLocaleDateString('ar-EG-u-nu-latn')}
                              </div>
                            </div>

                            {/* زر عرض البنود */}
                            {itemCount > 0 && (
                              <button
                                className="std-expand-btn"
                                onClick={e => { e.stopPropagation(); setExpandedId(isExpanded ? null : draft.id) }}
                                aria-label="عرض البنود"
                              >
                                {isExpanded ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
                              </button>
                            )}
                          </div>

                          {/* البنود المفصّلة */}
                          {isExpanded && draft.items && draft.items.length > 0 && (
                            <div className="std-draft-items">
                              {draft.items.map(item => (
                                <div key={item.id} className="std-item-row">
                                  <Package size={12} style={{ color: 'var(--text-muted)', flexShrink: 0 }} />
                                  <span className="std-item-name">{item.product?.name ?? '—'}</span>
                                  <span className="std-item-qty">
                                    {item.quantity} {item.unit?.symbol ?? ''}
                                  </span>
                                </div>
                              ))}
                            </div>
                          )}
                        </div>
                      )
                    })}
                  </div>
                </>
              )}
            </div>
          )}

          {/* ══ الخطوة 2: تحليل ومخزن ════════════════════════════════════ */}
          {step === 2 && (
            <div className="std-step-content animate-enter">
              {/* مخزن الوجهة — تلقائي إن وُجد، أو يدوي */}
              {myWarehouse ? (
                <div className="std-info-banner">
                  <Warehouse size={16} style={{ flexShrink: 0 }} />
                  <span>سيُضاف المخزون إلى: <strong>{myWarehouse.name}</strong> <span style={{ fontSize: 'var(--text-xs)', opacity: .7 }}>(مخزنك الافتراضي)</span></span>
                </div>
              ) : (
                <>
                  <div className="std-section-title">
                    <Warehouse size={14} />
                    مخزن الوجهة (مخزنك)
                    <span className="std-required">*</span>
                  </div>
                  <div className="std-warehouse-grid">
                    {destWarehouses.map(w => (
                      <button
                        key={w.id}
                        className={`std-warehouse-card ${selectedDestId === w.id ? 'selected' : ''}`}
                        onClick={() => setSelectedDestId(w.id)}
                        type="button"
                      >
                        <div className="std-wh-icon"><Warehouse size={18} /></div>
                        <div className="std-wh-info">
                          <div className="std-wh-name">{w.name}</div>
                          <div className="std-wh-type">{{ fixed: 'ثابت', vehicle: 'عربية', retail: 'نقطة بيع' }[w.type] ?? w.type}</div>
                        </div>
                        {selectedDestId === w.id && <CheckCircle2 size={16} style={{ color: 'var(--color-primary)', marginRight: 'auto' }} />}
                      </button>
                    ))}
                  </div>
                </>
              )}

              {/* جدول المنتجات */}
              <div className="std-section-title">
                <Package size={14} />
                المنتجات المطلوبة ({productNeeds.length})
              </div>

              <div className="std-product-table">
                {/* Header */}
                <div className="std-table-head">
                  <span>المنتج</span>
                  <span style={{ textAlign: 'center' }}>مطلوب</span>
                  <span style={{ textAlign: 'center' }}>متاح</span>
                  <span style={{ textAlign: 'center' }}>نقص</span>
                </div>

                {productNeeds.length === 0 ? (
                  <div className="std-no-items">
                    <CheckCircle2 size={20} style={{ color: 'var(--color-success)' }} />
                    <span>لا توجد منتجات ناقصة — المخزون كافٍ</span>
                  </div>
                ) : (
                  productNeeds.map((n) => (
                    <div
                      key={n.product_id + n.unit_id}
                      className={`std-table-row ${n.needed_qty > 0 ? 'has-shortage' : ''}`}
                    >
                      <div className="std-product-cell">
                        <div className="std-product-name">{n.product_name}</div>
                        <div className="std-product-sku" dir="ltr">{n.product_sku}</div>
                        <div className="std-product-orders">
                          {n.from_orders.slice(0, 2).join(', ')}
                          {n.from_orders.length > 2 && ` +${n.from_orders.length - 2}`}
                        </div>
                      </div>
                      <div className="std-qty-cell">
                        {formatNumber(n.total_qty)} <span className="std-unit">{n.unit_symbol}</span>
                      </div>
                      <div className={`std-qty-cell ${n.available_qty >= n.total_qty ? 'ok' : 'low'}`}>
                        {formatNumber(n.available_qty)}
                      </div>
                      <div className={`std-qty-cell ${n.needed_qty > 0 ? 'shortage' : 'ok'}`}>
                        {n.needed_qty > 0 ? (
                          <><AlertTriangle size={11} /> {formatNumber(n.needed_qty)}</>
                        ) : (
                          <CheckCircle2 size={12} />
                        )}
                      </div>
                    </div>
                  ))
                )}
              </div>

              {/* اختيار مخزن المصدر */}
              {shortageItems.length > 0 && (
                <>
                  <div className="std-section-title" style={{ marginTop: 'var(--space-5)' }}>
                    <Warehouse size={14} />
                    المخزن المصدر
                    <span className="std-required">*</span>
                  </div>

                  <div className="std-warehouse-grid">
                    {sourceWarehouses.map(w => (
                      <button
                        key={w.id}
                        className={`std-warehouse-card ${selectedSourceId === w.id ? 'selected' : ''}`}
                        onClick={() => setSelectedSourceId(w.id)}
                        type="button"
                      >
                        <div className="std-wh-icon">
                          <Warehouse size={18} />
                        </div>
                        <div className="std-wh-info">
                          <div className="std-wh-name">{w.name}</div>
                          <div className="std-wh-type">
                            {{ fixed: 'ثابت', vehicle: 'عربية', retail: 'نقطة بيع' }[w.type] ?? w.type}
                          </div>
                        </div>
                        {selectedSourceId === w.id && (
                          <CheckCircle2 size={16} style={{ color: 'var(--color-primary)', marginRight: 'auto' }} />
                        )}
                      </button>
                    ))}
                  </div>

                  {shortageItems.length > 0 && !selectedSourceId && (
                    <div className="std-hint">
                      <Info size={14} />
                      اختر المخزن الذي ستطلب منه البضاعة الناقصة
                    </div>
                  )}
                </>
              )}
            </div>
          )}

          {/* ══ الخطوة 3: المراجعة الأخيرة ═══════════════════════════════ */}
          {step === 3 && (
            <div className="std-step-content animate-enter">
              <div className="std-review-card">
                {/* مسار التحويل */}
                <div className="std-transfer-path">
                  <div className="std-path-node source">
                    <Warehouse size={16} />
                    <span>{allWarehouses.find(w => w.id === selectedSourceId)?.name ?? '—'}</span>
                    <small>مخزن المصدر</small>
                  </div>
                  <div className="std-path-arrow">
                    <ArrowLeft size={20} style={{ color: 'var(--color-primary)' }} />
                  </div>
                  <div className="std-path-node dest">
                    <Warehouse size={16} />
                    <span>{destWarehouse?.name ?? '—'}</span>
                    <small>مخزن الوجهة</small>
                  </div>
                </div>

                {/* المسودات */}
                <div className="std-review-section">
                  <div className="std-review-label">
                    <ShoppingCart size={13} /> المسودات المُدرجة ({selectedDrafts.length})
                  </div>
                  <div className="std-review-tags">
                    {selectedDrafts.map(d => (
                      <span key={d.id} className="std-order-tag" dir="ltr">{d.order_number}</span>
                    ))}
                  </div>
                </div>

                {/* المنتجات */}
                <div className="std-review-section">
                  <div className="std-review-label">
                    <Package size={13} /> المنتجات المطلوبة ({shortageItems.length})
                  </div>
                  <div className="std-review-items">
                    {shortageItems.map(n => (
                      <div key={n.product_id + n.unit_id} className="std-review-item">
                        <span className="std-ri-name">{n.product_name}</span>
                        <span className="std-ri-qty">
                          {formatNumber(n.needed_qty)} {n.unit_symbol}
                        </span>
                      </div>
                    ))}
                  </div>
                </div>

                {/* تنبيه */}
                <div className="std-alert-info">
                  <Info size={14} style={{ flexShrink: 0 }} />
                  <span>
                    سيُرسَل إشعار لمدير المخزن المصدر لمراجعة الطلب والموافقة على الشحن.
                    بعد الموافقة والشحن ستتمكن من تأكيد مسوداتك.
                  </span>
                </div>
              </div>
            </div>
          )}

        </div>

        {/* ─── Footer ──────────────────────────────────────────────────── */}
        <div className="std-footer">
          {/* زر الرجوع */}
          {step > 1 && (
            <button
              className="std-btn std-btn-ghost"
              onClick={() => setStep(s => (s - 1) as 1 | 2 | 3)}
              disabled={creating}
            >
              <ArrowRight size={15} />
              رجوع
            </button>
          )}

          {step === 1 && (
            <button className="std-btn std-btn-ghost" onClick={onClose}>
              إلغاء
            </button>
          )}

          {/* زر الإجراء الرئيسي */}
          <div style={{ flex: 1 }} />

          {step === 1 && (
            <button
              className="std-btn std-btn-primary"
              onClick={analyzeStock}
              disabled={selectedIds.size === 0 || analyzingStock}
            >
              {analyzingStock
                ? <><Loader2 size={15} className="std-spin" /> جاري التحليل...</>
                : <>{selectedIds.size > 0 ? `تحليل ${selectedIds.size} مسودة` : 'اختر مسودة أولاً'} <ArrowLeft size={15} /></>
              }
            </button>
          )}

          {step === 2 && shortageItems.length === 0 && (
            <div className="std-no-shortage">
              <CheckCircle2 size={16} />
              المخزون كافٍ — لا حاجة لتحويل
            </div>
          )}

          {step === 2 && shortageItems.length > 0 && (
            <button
              className="std-btn std-btn-primary"
              onClick={() => setStep(3)}
              disabled={!selectedSourceId || !selectedDestId}
            >
              مراجعة التحويل <ArrowLeft size={15} />
            </button>
          )}

          {step === 3 && (
            <button
              className="std-btn std-btn-success"
              onClick={handleCreateTransfer}
              disabled={creating}
            >
              {creating
                ? <><Loader2 size={15} className="std-spin" /> جاري الإنشاء...</>
                : <><Zap size={15} /> إنشاء طلب التحويل</>
              }
            </button>
          )}
        </div>
      </div>

      {/* ─── Styles ────────────────────────────────────────────────────── */}
      <style>{`
        /* ─── Dialog Reset ─── */
        #smart-transfer-dialog::backdrop {
          background: rgba(15,23,42,.55);
          backdrop-filter: blur(4px);
        }

        .std-wrapper {
          display: flex;
          flex-direction: column;
          height: 100%;
          max-height: 92vh;
          overflow: hidden;
        }

        /* ─── Header ─── */
        .std-header {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-4) var(--space-5);
          border-bottom: 1px solid var(--border-subtle);
          flex-shrink: 0;
          background: var(--bg-surface);
        }
        .std-header-info { display: flex; align-items: center; gap: var(--space-3); }
        .std-header-icon {
          width: 40px; height: 40px;
          border-radius: var(--radius-xl);
          background: linear-gradient(135deg, var(--color-primary), #6d28d9);
          display: flex; align-items: center; justify-content: center;
          color: #fff;
          box-shadow: 0 4px 12px rgba(37,99,235,.3);
          flex-shrink: 0;
        }
        .std-title {
          font-size: var(--text-lg);
          font-weight: 700;
          color: var(--text-primary);
          margin: 0;
        }
        .std-subtitle {
          font-size: var(--text-xs);
          color: var(--text-muted);
          margin: 2px 0 0;
        }
        .std-close-btn {
          width: 32px; height: 32px;
          border: none; border-radius: 50%;
          background: var(--bg-surface-2);
          cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          color: var(--text-muted);
          transition: background .15s, color .15s;
        }
        .std-close-btn:hover { background: var(--color-danger-light); color: var(--color-danger); }

        /* ─── Stepper ─── */
        .std-stepper {
          display: flex;
          align-items: center;
          justify-content: center;
          padding: var(--space-3) var(--space-5);
          background: var(--bg-surface-2);
          border-bottom: 1px solid var(--border-subtle);
          flex-shrink: 0;
          gap: 0;
        }
        .std-step {
          display: flex;
          align-items: center;
          gap: var(--space-2);
          position: relative;
        }
        .std-step-dot {
          width: 28px; height: 28px;
          border-radius: 50%;
          background: var(--bg-surface);
          border: 2px solid var(--border-subtle);
          display: flex; align-items: center; justify-content: center;
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--text-muted);
          transition: all .25s;
          flex-shrink: 0;
        }
        .std-step.active .std-step-dot {
          border-color: var(--color-primary);
          background: var(--color-primary);
          color: #fff;
          box-shadow: 0 0 0 3px var(--color-primary-light);
        }
        .std-step.done .std-step-dot {
          border-color: var(--color-success);
          background: var(--color-success);
          color: #fff;
        }
        .std-step-label {
          font-size: var(--text-xs);
          font-weight: 600;
          color: var(--text-muted);
          transition: color .25s;
        }
        .std-step.active .std-step-label { color: var(--color-primary); }
        .std-step.done  .std-step-label { color: var(--color-success); }
        .std-step-line {
          width: 40px;
          height: 2px;
          background: var(--border-subtle);
          margin: 0 var(--space-2);
          flex-shrink: 0;
        }

        /* ─── Body ─── */
        .std-body {
          flex: 1;
          overflow-y: auto;
          padding: var(--space-4) var(--space-5);
          overscroll-behavior: contain;
        }
        .std-step-content { display: flex; flex-direction: column; gap: var(--space-3); }

        /* ─── Loading & Empty ─── */
        .std-loading, .std-empty {
          display: flex; flex-direction: column; align-items: center;
          justify-content: center; gap: var(--space-3);
          padding: var(--space-10);
          color: var(--text-muted); text-align: center;
        }
        .std-empty-title { font-weight: 600; font-size: var(--text-base); color: var(--text-primary); margin: 0; }
        .std-empty-sub  { font-size: var(--text-sm); margin: 0; }
        .std-spin { animation: spin 1s linear infinite; color: var(--color-primary); }
        @keyframes spin { to { transform: rotate(360deg); } }

        /* ─── Draft Controls ─── */
        .std-action-bar {
          display: flex;
          align-items: center;
          justify-content: space-between;
          padding: var(--space-2) var(--space-3);
          background: var(--bg-surface-2);
          border-radius: var(--radius-lg);
        }
        .std-count-badge {
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--color-primary);
          background: var(--color-primary-light);
          padding: 2px 10px;
          border-radius: 9999px;
        }
        .std-link-btn {
          background: none; border: none; cursor: pointer;
          color: var(--color-primary);
          font-size: var(--text-xs); font-weight: 600;
          padding: 4px 8px; border-radius: var(--radius-md);
          transition: background .15s;
        }
        .std-link-btn:hover { background: var(--color-primary-light); }

        /* ─── Draft List ─── */
        .std-draft-list { display: flex; flex-direction: column; gap: var(--space-2); }
        .std-draft-card {
          border: 1.5px solid var(--border-subtle);
          border-radius: var(--radius-xl);
          overflow: hidden;
          transition: border-color .15s, box-shadow .15s;
          background: var(--bg-surface);
        }
        .std-draft-card.selected {
          border-color: var(--color-primary);
          box-shadow: 0 0 0 3px var(--color-primary-light);
        }
        .std-draft-main {
          display: flex;
          align-items: center;
          gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          cursor: pointer;
          user-select: none;
          transition: background .12s;
        }
        .std-draft-main:hover { background: var(--bg-hover); }
        .std-checkbox {
          width: 22px; height: 22px;
          border-radius: var(--radius-md);
          border: 2px solid var(--border-default);
          display: flex; align-items: center; justify-content: center;
          flex-shrink: 0;
          transition: all .15s;
          color: #fff;
        }
        .std-checkbox.checked {
          background: var(--color-primary);
          border-color: var(--color-primary);
        }
        .std-draft-info { flex: 1; min-width: 0; }
        .std-draft-num {
          font-family: monospace;
          font-size: var(--text-xs);
          font-weight: 700;
          color: var(--color-primary);
          letter-spacing: .04em;
        }
        .std-draft-customer {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
          overflow: hidden;
          text-overflow: ellipsis;
          white-space: nowrap;
        }
        .std-draft-meta { text-align: end; flex-shrink: 0; }
        .std-draft-amount {
          font-size: var(--text-sm);
          font-weight: 700;
          color: var(--text-primary);
          font-variant-numeric: tabular-nums;
        }
        .std-draft-date { font-size: 10px; color: var(--text-muted); }
        .std-expand-btn {
          background: none; border: none;
          width: 28px; height: 28px;
          border-radius: 50%;
          cursor: pointer;
          display: flex; align-items: center; justify-content: center;
          color: var(--text-muted);
          transition: background .12s;
          flex-shrink: 0;
        }
        .std-expand-btn:hover { background: var(--bg-surface-2); }

        /* ─── Draft Items ─── */
        .std-draft-items {
          padding: var(--space-2) var(--space-4) var(--space-3);
          border-top: 1px solid var(--border-subtle);
          background: var(--bg-surface-2);
          display: flex; flex-direction: column; gap: 4px;
        }
        .std-item-row {
          display: flex; align-items: center; gap: 6px;
          font-size: var(--text-xs);
        }
        .std-item-name { flex: 1; color: var(--text-secondary); }
        .std-item-qty {
          font-variant-numeric: tabular-nums;
          font-weight: 600;
          color: var(--text-primary);
        }

        /* ─── Step 2 — Analysis ─── */
        .std-info-banner {
          display: flex; align-items: center; gap: var(--space-2);
          padding: var(--space-3) var(--space-4);
          background: var(--color-info-light, rgba(2,132,199,.08));
          border: 1px solid rgba(2,132,199,.2);
          border-radius: var(--radius-xl);
          font-size: var(--text-sm);
          color: var(--color-info, #0284c7);
        }
        .std-section-title {
          display: flex; align-items: center; gap: var(--space-2);
          font-size: var(--text-xs);
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: .06em;
          color: var(--text-muted);
        }
        .std-required { color: var(--color-danger); margin-right: 2px; }

        /* ─── Product Table ─── */
        .std-product-table {
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-xl);
          overflow: hidden;
        }
        .std-table-head {
          display: grid;
          grid-template-columns: 1fr 80px 80px 80px;
          padding: var(--space-2) var(--space-4);
          background: var(--bg-surface-2);
          font-size: 10px;
          font-weight: 700;
          text-transform: uppercase;
          letter-spacing: .05em;
          color: var(--text-muted);
          gap: var(--space-2);
        }
        .std-table-row {
          display: grid;
          grid-template-columns: 1fr 80px 80px 80px;
          padding: var(--space-3) var(--space-4);
          border-top: 1px solid var(--border-subtle);
          gap: var(--space-2);
          align-items: center;
          transition: background .12s;
        }
        .std-table-row:hover { background: var(--bg-hover); }
        .std-table-row.has-shortage { background: rgba(220,38,38,.03); }
        .std-product-cell { min-width: 0; }
        .std-product-name {
          font-size: var(--text-sm);
          font-weight: 600;
          color: var(--text-primary);
          overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
        }
        .std-product-sku { font-size: 10px; color: var(--text-muted); font-family: monospace; }
        .std-product-orders { font-size: 10px; color: var(--color-primary); opacity: .8; }
        .std-qty-cell {
          text-align: center;
          font-size: var(--text-sm);
          font-weight: 600;
          font-variant-numeric: tabular-nums;
          display: flex; align-items: center; justify-content: center; gap: 3px;
        }
        .std-qty-cell.ok      { color: var(--color-success); }
        .std-qty-cell.low     { color: var(--color-warning); }
        .std-qty-cell.shortage{ color: var(--color-danger); }
        .std-unit { font-size: 10px; font-weight: 400; color: var(--text-muted); }
        .std-no-items {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-2);
          padding: var(--space-5);
          color: var(--color-success);
          font-size: var(--text-sm); font-weight: 600;
        }

        /* ─── Warehouse Grid ─── */
        .std-warehouse-grid {
          display: flex; flex-direction: column; gap: var(--space-2);
        }
        .std-warehouse-card {
          display: flex; align-items: center; gap: var(--space-3);
          padding: var(--space-3) var(--space-4);
          border: 1.5px solid var(--border-subtle);
          border-radius: var(--radius-xl);
          background: var(--bg-surface);
          cursor: pointer;
          text-align: start;
          transition: border-color .15s, box-shadow .15s;
          width: 100%;
        }
        .std-warehouse-card.selected {
          border-color: var(--color-primary);
          background: var(--color-primary-light);
          box-shadow: 0 0 0 3px rgba(37,99,235,.1);
        }
        .std-warehouse-card:hover:not(.selected) { border-color: var(--border-default); background: var(--bg-hover); }
        .std-wh-icon {
          width: 36px; height: 36px;
          border-radius: var(--radius-lg);
          background: var(--bg-accent);
          display: flex; align-items: center; justify-content: center;
          color: var(--color-primary); flex-shrink: 0;
        }
        .std-warehouse-card.selected .std-wh-icon { background: rgba(37,99,235,.15); }
        .std-wh-name { font-size: var(--text-sm); font-weight: 600; color: var(--text-primary); }
        .std-wh-type { font-size: var(--text-xs); color: var(--text-muted); }

        .std-hint {
          display: flex; align-items: flex-start; gap: var(--space-2);
          padding: var(--space-3);
          font-size: var(--text-xs);
          color: var(--text-muted);
        }

        /* ─── Step 3 — Review ─── */
        .std-review-card {
          border: 1px solid var(--border-subtle);
          border-radius: var(--radius-2xl);
          overflow: hidden;
          background: var(--bg-surface);
        }
        .std-transfer-path {
          display: flex; align-items: center; justify-content: center;
          gap: var(--space-4);
          padding: var(--space-5);
          background: linear-gradient(135deg, rgba(37,99,235,.05), rgba(109,40,217,.05));
          border-bottom: 1px solid var(--border-subtle);
        }
        .std-path-node {
          display: flex; flex-direction: column; align-items: center; gap: 4px;
          padding: var(--space-3) var(--space-4);
          border-radius: var(--radius-xl);
          background: var(--bg-surface-2);
          min-width: 120px;
          text-align: center;
        }
        .std-path-node span {
          font-size: var(--text-sm); font-weight: 700; color: var(--text-primary);
        }
        .std-path-node small { font-size: 10px; color: var(--text-muted); }
        .std-path-node.source { color: var(--color-warning); }
        .std-path-node.source svg { color: var(--color-warning); }
        .std-path-node.dest { color: var(--color-success); }
        .std-path-node.dest svg { color: var(--color-success); }
        .std-path-arrow { display: flex; flex-direction: column; align-items: center; gap: 4px; }

        .std-review-section {
          padding: var(--space-4) var(--space-5);
          border-bottom: 1px solid var(--border-subtle);
        }
        .std-review-label {
          display: flex; align-items: center; gap: 6px;
          font-size: var(--text-xs); font-weight: 700;
          color: var(--text-muted); text-transform: uppercase;
          letter-spacing: .05em; margin-bottom: var(--space-2);
        }
        .std-review-tags { display: flex; flex-wrap: wrap; gap: var(--space-2); }
        .std-order-tag {
          background: var(--color-primary-light);
          color: var(--color-primary);
          font-family: monospace; font-size: 11px; font-weight: 700;
          padding: 3px 10px; border-radius: 9999px;
        }
        .std-review-items { display: flex; flex-direction: column; gap: 6px; }
        .std-review-item {
          display: flex; align-items: center; justify-content: space-between;
          font-size: var(--text-sm);
        }
        .std-ri-name { color: var(--text-secondary); }
        .std-ri-qty  { font-weight: 700; color: var(--text-primary); font-variant-numeric: tabular-nums; }

        .std-alert-info {
          display: flex; align-items: flex-start; gap: var(--space-2);
          padding: var(--space-4) var(--space-5);
          font-size: var(--text-xs);
          color: var(--color-info, #0284c7);
          background: var(--color-info-light, rgba(2,132,199,.06));
          line-height: 1.5;
        }

        .std-no-shortage {
          display: flex; align-items: center; gap: var(--space-2);
          color: var(--color-success); font-size: var(--text-sm); font-weight: 600;
          padding: var(--space-2) var(--space-3);
        }

        /* ─── Footer ─── */
        .std-footer {
          display: flex; align-items: center;
          padding: var(--space-4) var(--space-5);
          border-top: 1px solid var(--border-subtle);
          gap: var(--space-3);
          flex-shrink: 0;
          background: var(--bg-surface);
        }
        .std-btn {
          display: flex; align-items: center; gap: var(--space-2);
          padding: 0 var(--space-5);
          height: 44px;
          border-radius: var(--radius-xl);
          border: none;
          cursor: pointer;
          font-size: var(--text-sm);
          font-weight: 600;
          font-family: inherit;
          transition: all .15s;
          white-space: nowrap;
        }
        .std-btn:disabled { opacity: .5; cursor: not-allowed; }
        .std-btn-ghost {
          background: var(--bg-surface-2);
          color: var(--text-secondary);
          border: 1px solid var(--border-subtle);
        }
        .std-btn-ghost:hover:not(:disabled) { background: var(--bg-hover); }
        .std-btn-primary {
          background: var(--color-primary);
          color: #fff;
          box-shadow: 0 4px 12px rgba(37,99,235,.25);
        }
        .std-btn-primary:hover:not(:disabled) { background: var(--color-primary-hover); box-shadow: 0 6px 16px rgba(37,99,235,.35); }
        .std-btn-success {
          background: var(--color-success);
          color: #fff;
          box-shadow: 0 4px 12px rgba(22,163,74,.25);
        }
        .std-btn-success:hover:not(:disabled) { filter: brightness(1.08); }

        /* ─── Entry Animation ─── */
        .animate-enter { animation: fade-up .2s ease-out; }
        @keyframes fade-up {
          from { opacity: 0; transform: translateY(6px); }
          to   { opacity: 1; transform: translateY(0); }
        }

        /* ─── Mobile ─── */
        @media (max-width: 640px) {
          #smart-transfer-dialog {
            max-width: 100vw;
            width: 100%;
            max-height: 95vh;
            border-radius: var(--radius-2xl) var(--radius-2xl) 0 0;
            position: fixed;
            bottom: 0;
            margin: 0;
          }
          .std-stepper { gap: 0; padding: var(--space-2) var(--space-3); }
          .std-step-line { width: 24px; }
          .std-step-label { display: none; }
          .std-table-head, .std-table-row {
            grid-template-columns: 1fr 60px 60px 60px;
          }
          .std-transfer-path { flex-direction: column; gap: var(--space-3); }
          .std-path-arrow { transform: rotate(90deg); }
          .std-path-node { width: 100%; }
          .std-body { padding: var(--space-3) var(--space-4); }
          .std-footer { padding: var(--space-3) var(--space-4); }
        }
      `}</style>
    </dialog>
  )
}
