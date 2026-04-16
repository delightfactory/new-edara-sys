/**
 * CustomerCreditPanel — اللوحة الجانبية (Drawer) للعميل في صفحة إدارة الائتمان
 *
 * الهيكل:
 *   - Header فوري من بيانات الصف (لا طلب)
 *   - Tab 1: الفواتير المفتوحة (يُحمَّل عند فتح الـ Drawer)
 *   - Tab 2: سجل تغييرات حد الائتمان (يُحمَّل عند الضغط)
 *   - Tab 3: آخر 10 حركات (يُحمَّل عند الضغط)
 *   - Tab 4: تعديل البنود (لمن يملك customers.credit.update فقط)
 *
 * الأداء:
 *   - كل Tab يُحمَّل مرة واحدة فقط ثم يُحفظ في Cache
 *   - إعادة فتح نفس العميل لا تُعيد الطلبات
 *
 * القيود:
 *   - لا رصيد افتتاحي في أي موضع
 *   - لا استدعاء لـ getOpenOrdersForCustomer() من payments.ts
 *   - لا استدعاء لـ updateCustomer() من customers.ts
 *   - لا استدعاء لـ update_customer_with_opening_balance
 */

import { useState } from 'react'
import { useQuery, useQueryClient } from '@tanstack/react-query'
import { toast } from 'sonner'

import { useAuthStore }      from '@/stores/auth-store'
import { PERMISSIONS }       from '@/lib/permissions/constants'
import { getCreditHistory }  from '@/lib/services/customers'
import { getCustomerLedger } from '@/lib/services/finance'
import {
  getCreditOpenOrders,
  creditUpdateCustomer,
} from '@/lib/services/credit'
import { computeCreditState } from '@/components/shared/CustomerCreditChip'
import { formatNumber, formatDate, formatCurrency } from '@/lib/utils/format'
import type { Customer } from '@/lib/types/master-data'

// ─────────────────────────────────────────────────────────────
// Props
// ─────────────────────────────────────────────────────────────

interface CustomerCreditPanelProps {
  customer:  Customer
  onClose:   () => void
  onUpdated: () => void
}

type TabId = 'invoices' | 'history' | 'ledger' | 'edit'

// ─────────────────────────────────────────────────────────────
// Component
// ─────────────────────────────────────────────────────────────

export default function CustomerCreditPanel({
  customer,
  onClose,
  onUpdated,
}: CustomerCreditPanelProps) {
  const can        = useAuthStore(s => s.can)
  const canEdit    = can(PERMISSIONS.CUSTOMERS_CREDIT_UPDATE)
  const qc         = useQueryClient()

  const [activeTab, setActiveTab] = useState<TabId>('invoices')

  // رأس اللوحة — فوري من بيانات الصف
  const state = computeCreditState({
    payment_terms:   customer.payment_terms,
    credit_limit:    customer.credit_limit,
    current_balance: customer.current_balance,
  })

  const usedPct = state.type === 'credit' ? state.usedPct : 0
  const accent  = state.type === 'credit' ?  state.accent :
                  state.type === 'cash'   ? '#2563eb'     : '#64748b'

  // ── Tab 1: الفواتير المفتوحة ────────────────────────────────
  const { data: openOrders, isLoading: loadingOrders } = useQuery({
    queryKey:  ['credit-open-orders', customer.id],
    queryFn:   () => getCreditOpenOrders(customer.id),
    staleTime: 90_000,
    enabled:   activeTab === 'invoices',
  })

  // ── Tab 2: سجل تغييرات حد الائتمان ────────────────────────
  const { data: creditHistory, isLoading: loadingHistory } = useQuery({
    queryKey:  ['credit-history', customer.id],
    queryFn:   () => getCreditHistory(customer.id),
    staleTime: 90_000,
    enabled:   activeTab === 'history',
  })

  // ── Tab 3: آخر 10 حركات ────────────────────────────────────
  const { data: ledgerResult, isLoading: loadingLedger } = useQuery({
    queryKey:  ['credit-ledger', customer.id],
    queryFn:   () => getCustomerLedger(customer.id, { page: 1, pageSize: 10 }),
    staleTime: 90_000,
    enabled:   activeTab === 'ledger',
  })

  // ── Tab 4: نموذج التعديل ───────────────────────────────────
  const [editForm, setEditForm] = useState({
    payment_terms: customer.payment_terms || 'cash',
    credit_limit:  customer.credit_limit  || 0,
    credit_days:   customer.credit_days   || 0,
  })
  const [saving, setSaving]     = useState(false)

  const isCashConvert =
    (customer.payment_terms !== 'cash') && editForm.payment_terms === 'cash'
  const isLimitBelow =
    editForm.payment_terms !== 'cash' &&
    editForm.credit_limit < (customer.current_balance || 0)

  async function handleSave() {
    if (saving) return

    // ── التحقق الهيكلي قبل الإرسال ────────────────────────────
    // 1. طريقة الدفع: قيمة صالحة
    if (!['cash', 'credit', 'mixed'].includes(editForm.payment_terms)) {
      toast.error('طريقة الدفع غير صالحة')
      return
    }
    // 2. الحد الائتماني: عدد غير سالب
    if (isNaN(editForm.credit_limit) || editForm.credit_limit < 0) {
      toast.error('الحد الائتماني يجب أن يكون صفراً أو أكبر')
      return
    }
    // 3. مدة السداد: عدد صحيح غير سالب
    if (!Number.isInteger(editForm.credit_days) || editForm.credit_days < 0) {
      toast.error('مدة السداد يجب أن تكون عدداً صحيحاً غير سالب')
      return
    }
    // 4. تحذيري (لا يمنع الحفظ) — التجاوز والتحويل لنقدي معروضان بصرياً
    // ─────────────────────────────────────────────────────────────

    setSaving(true)
    try {
      await creditUpdateCustomer(customer.id, {
        payment_terms: editForm.payment_terms,
        credit_limit:  editForm.credit_limit,
        credit_days:   editForm.credit_days,
      })
      toast.success('تم تحديث البنود الائتمانية')

      await qc.invalidateQueries({ queryKey: ['credit-portfolio-kpis'] })
      await qc.invalidateQueries({ queryKey: ['customers'] })
      await qc.invalidateQueries({ queryKey: ['credit-open-orders', customer.id] })
      await qc.invalidateQueries({ queryKey: ['credit-history', customer.id] })

      onUpdated()
    } catch (err: any) {
      toast.error(err?.message || 'حدث خطأ أثناء الحفظ')
    } finally {
      setSaving(false)
    }
  }

  // ─────────────────────────────────────────────────────────────
  // التبويبات المتاحة
  // ─────────────────────────────────────────────────────────────
  const tabs: { id: TabId; label: string; icon: string }[] = [
    { id: 'invoices', label: 'المسلَّمة',  icon: '📄' },   // مسلَّم فقط — لا confirmed
    { id: 'history',  label: 'سجل الحد',  icon: '📋' },
    { id: 'ledger',   label: 'الحركات',   icon: '💰' },
    ...(canEdit ? [{ id: 'edit' as TabId, label: 'تعديل', icon: '✏️' }] : []),
  ]

  // ─────────────────────────────────────────────────────────────
  // Render
  // ─────────────────────────────────────────────────────────────
  return (
    <div id="customer-credit-panel" style={{
      position:        'fixed',
      top:             0,
      insetInlineEnd:  0,
      bottom:          0,
      width:           440,
      maxWidth:        '100vw',
      background:      'var(--bg-surface)',
      borderInlineStart: `1px solid var(--border-primary)`,
      boxShadow:       'var(--shadow-lg)',
      display:         'flex',
      flexDirection:   'column',
      zIndex:          300,
      animation:       'panel-slide-in 0.25s cubic-bezier(0.4,0,0.2,1)',
    }}>

      {/* ── Header ────────────────────────────────────────────── */}
      <div style={{
        padding:        '16px 18px',
        borderBottom:   `1px solid var(--border-primary)`,
        background:     'var(--bg-surface)',
        flexShrink:     0,
      }}>
        {/* Row 1: اسم + زر إغلاق */}
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <div>
            <div style={{ fontSize: 'var(--text-lg)', fontWeight: 700, color: 'var(--text-primary)' }}>
              {customer.name}
            </div>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
              {customer.code}
              {customer.assigned_rep && ` • ${(customer.assigned_rep as any)?.full_name}`}
            </div>
          </div>
          <button
            id="panel-close-btn"
            onClick={onClose}
            style={{
              border: 'none', background: 'var(--bg-surface-2)',
              borderRadius: 8, width: 32, height: 32,
              cursor: 'pointer', color: 'var(--text-secondary)',
              fontSize: '1rem', display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}
          >✕</button>
        </div>

        {/* Row 2: أرقام ائتمانية */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr',
          gap: 8, marginBottom: 8,
        }}>
          <div style={{
            background: 'var(--bg-surface-2)', borderRadius: 8,
            padding: '8px 12px',
          }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>الحد / المستخدم</div>
            <div style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--text-primary)', marginTop: 2 }}>
              {state.type === 'credit' ? (
                <>{formatNumber(state.balance)} / {formatNumber(state.limit)}</>
              ) : state.type === 'cash' ? (
                <span style={{ color: '#2563eb' }}>نقدي</span>
              ) : (
                <span style={{ color: '#64748b' }}>غير محدود</span>
              )}
            </div>
          </div>
          <div style={{
            background: 'var(--bg-surface-2)', borderRadius: 8,
            padding: '8px 12px',
          }}>
            <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>طريقة الدفع / المدة</div>
            <div style={{ fontSize: 'var(--text-sm)', fontWeight: 700, color: 'var(--text-primary)', marginTop: 2 }}>
              {translatePaymentTerms(customer.payment_terms)}
              {customer.credit_days ? ` • ${customer.credit_days} يوم` : ''}
            </div>
          </div>
        </div>

        {/* Progress bar */}
        {state.type === 'credit' && (
          <div>
            <div style={{
              display: 'flex', justifyContent: 'space-between',
              fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 4,
            }}>
              <span style={{ fontWeight: 600, color: accent }}>
                {state.label}
              </span>
              <span>{Math.round(usedPct * 100)}% مستخدم</span>
            </div>
            <div style={{ height: 6, borderRadius: 99, background: 'var(--bg-surface-2)', overflow: 'hidden' }}>
              <div style={{
                height: '100%', borderRadius: 99,
                width: `${usedPct * 100}%`,
                background: `linear-gradient(to left, ${accent}, ${state.gradFrom})`,
                transition: 'width 0.45s ease',
              }} />
            </div>
          </div>
        )}
      </div>

      {/* ── Tabs ──────────────────────────────────────────────── */}
      <div style={{
        display: 'flex',
        borderBottom: `1px solid var(--border-primary)`,
        overflow: 'hidden',
        flexShrink: 0,
      }}>
        {tabs.map(tab => (
          <button
            key={tab.id}
            id={`panel-tab-${tab.id}`}
            onClick={() => setActiveTab(tab.id)}
            style={{
              flex:             1,
              padding:          '10px 6px',
              border:           'none',
              background:       activeTab === tab.id ? 'var(--color-primary-light)' : 'transparent',
              color:            activeTab === tab.id ? 'var(--color-primary)' : 'var(--text-secondary)',
              borderBottom:     activeTab === tab.id ? `2px solid var(--color-primary)` : '2px solid transparent',
              fontFamily:       'var(--font-sans)',
              fontSize:         'var(--text-xs)',
              fontWeight:       600,
              cursor:           'pointer',
              display:          'flex',
              alignItems:       'center',
              justifyContent:   'center',
              gap:              4,
              transition:       'all 0.15s',
            }}
          >
            <span>{tab.icon}</span>
            <span>{tab.label}</span>
          </button>
        ))}
      </div>

      {/* ── Tab Content ───────────────────────────────────────── */}
      <div style={{
        flex:      1,
        overflowY: 'auto',
        padding:   '14px 16px',
      }}>

        {/* ── Tab 1: الفواتير المفتوحة ──────────────────────── */}
        {activeTab === 'invoices' && (
          loadingOrders ? <TabSkeleton /> : (
            <InvoicesTab
              orders={openOrders || []}
              creditDays={customer.credit_days || 0}
            />
          )
        )}

        {/* ── Tab 2: سجل تغييرات حد الائتمان ──────────────── */}
        {activeTab === 'history' && (
          loadingHistory ? <TabSkeleton /> : (
            <CreditHistoryTab history={creditHistory || []} />
          )
        )}

        {/* ── Tab 3: آخر 10 حركات ──────────────────────────── */}
        {activeTab === 'ledger' && (
          loadingLedger ? <TabSkeleton /> : (
            <LedgerTab
              entries={ledgerResult?.data || []}
              customerId={customer.id}
            />
          )
        )}

        {/* ── Tab 4: تعديل البنود ──────────────────────────── */}
        {activeTab === 'edit' && canEdit && (
          <EditTab
            editForm={editForm}
            setEditForm={setEditForm}
            currentBalance={customer.current_balance || 0}
            isCashConvert={isCashConvert}
            isLimitBelow={isLimitBelow}
            saving={saving}
            onSave={handleSave}
            onCancel={() => {
              setEditForm({
                payment_terms: customer.payment_terms || 'cash',
                credit_limit:  customer.credit_limit  || 0,
                credit_days:   customer.credit_days   || 0,
              })
            }}
          />
        )}
      </div>

      {/* ── Footer Links ──────────────────────────────────────── */}
      <div style={{
        padding:     '10px 16px',
        borderTop:   `1px solid var(--border-primary)`,
        display:     'flex',
        gap:         8,
        flexShrink:  0,
      }}>
        <a
          href={`/customers/${customer.id}`}
          style={{
            flex: 1,
            padding: '8px 12px',
            textAlign: 'center',
            background: 'var(--bg-surface-2)',
            border: '1px solid var(--border-primary)',
            borderRadius: 8,
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-sans)',
            fontSize: 'var(--text-xs)',
            fontWeight: 600,
            textDecoration: 'none',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
          }}
        >
          🔗 الملف الكامل
        </a>
        <a
          href={`/finance/payments?customer=${customer.id}`}
          style={{
            flex: 1,
            padding: '8px 12px',
            textAlign: 'center',
            background: 'var(--color-primary)',
            border: 'none',
            borderRadius: 8,
            color: '#fff',
            fontFamily: 'var(--font-sans)',
            fontSize: 'var(--text-xs)',
            fontWeight: 600,
            textDecoration: 'none',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 4,
          }}
        >
          📥 تسجيل دفعة
        </a>
      </div>

      <style>{`
        @keyframes panel-slide-in {
          from { transform: translateX(-100%); opacity: 0; }
          to   { transform: translateX(0); opacity: 1; }
        }
      `}</style>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Sub-components
// ─────────────────────────────────────────────────────────────

function TabSkeleton() {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {[1,2,3,4].map(i => (
        <div key={i} className="skeleton" style={{ height: 52, borderRadius: 8 }} />
      ))}
    </div>
  )
}

// ── Tab 1: الفواتير ───────────────────────────────────────────
function InvoicesTab({ orders, creditDays }: {
  orders: import('@/lib/services/credit').CreditOpenOrder[]
  creditDays: number
}) {
  if (!orders.length) {
    return (
      <div style={{ textAlign: 'center', padding: '32px 0', color: 'var(--text-muted)' }}>
        <div style={{ fontSize: '2rem', marginBottom: 8 }}>📭</div>
        <div style={{ fontWeight: 600 }}>لا توجد فواتير مفتوحة</div>
        <div style={{ fontSize: 'var(--text-xs)', marginTop: 4 }}>جميع مستحقات هذا العميل مسددة</div>
      </div>
    )
  }

  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 8 }}>
      {orders.map(order => {
        const daysNum = order.days_since_delivery ?? 0
        const isOverdue = daysNum > creditDays
        const isWarn    = !isOverdue && creditDays > 0 && daysNum > creditDays * 0.7

        const dayColor = isOverdue ? '#dc2626' : isWarn ? '#d97706' : '#16a34a'

        return (
          <div key={order.id} style={{
            background:   'var(--bg-surface-2)',
            border:       `1px solid var(--border-primary)`,
            borderRadius: 10,
            padding:      '10px 12px',
          }}>
            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
              <span style={{ fontWeight: 700, fontSize: 'var(--text-sm)', color: 'var(--text-primary)' }}>
                {order.order_number}
              </span>
              <span style={{
                fontSize: 'var(--text-xs)', fontWeight: 700,
                color: dayColor,
                background: `${dayColor}15`,
                padding: '2px 8px', borderRadius: 99,
              }}>
                {/* days_since_delivery دائمًا موجودة لأن كل الطلبات مسلَّمة */}
                {order.days_since_delivery != null
                  ? `${order.days_since_delivery} يوم`
                  : '—'
                }
              </span>
            </div>

            <div style={{
              display: 'grid', gridTemplateColumns: '1fr 1fr 1fr 1fr',
              gap: 4, fontSize: 'var(--text-xs)',
            }}>
              <div>
                <div style={{ color: 'var(--text-muted)' }}>الإجمالي</div>
                <div style={{ fontWeight: 600, color: 'var(--text-primary)' }}>
                  {formatNumber(order.total_amount)}
                </div>
              </div>
              <div>
                <div style={{ color: 'var(--text-muted)' }}>المدفوع</div>
                <div style={{ fontWeight: 600, color: '#16a34a' }}>
                  {formatNumber(order.paid_amount)}
                </div>
              </div>
              <div>
                <div style={{ color: 'var(--text-muted)' }}>المرتجع</div>
                <div style={{ fontWeight: 600, color: '#2563eb' }}>
                  {formatNumber(order.returned_amount)}
                </div>
              </div>
              <div>
                <div style={{ color: 'var(--text-muted)' }}>الصافي المتبقي</div>
                <div style={{ fontWeight: 700, color: dayColor }}>
                  {formatNumber(order.net_remaining)}
                </div>
              </div>
            </div>

            {order.delivered_at && (
              <div style={{
                marginTop: 6,
                fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
              }}>
                تاريخ التسليم: {formatDate(order.delivered_at)}
              </div>
            )}
          </div>
        )
      })}
    </div>
  )
}

// ── Tab 2: سجل تغييرات حد الائتمان ──────────────────────────
function CreditHistoryTab({ history }: { history: any[] }) {
  return (
    <div>
      {/* ملاحظة صادقة وواضحة */}
      <div style={{
        background:   'rgba(217,119,6,0.08)',
        border:       '1px solid rgba(217,119,6,0.2)',
        borderRadius: 8,
        padding:      '8px 12px',
        marginBottom: 12,
        fontSize:     'var(--text-xs)',
        color:        '#92400e',
      }}>
        ⚠️ <strong>سجل تغييرات حد الائتمان فقط</strong> — تغييرات طريقة الدفع ومدة السداد غير مُسجَّلة هنا
      </div>

      {!history.length ? (
        <div style={{ textAlign: 'center', padding: '24px 0', color: 'var(--text-muted)' }}>
          <div style={{ fontSize: '2rem', marginBottom: 8 }}>📋</div>
          <div style={{ fontWeight: 600 }}>لا يوجد سجل تغييرات</div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {history.map((entry: any) => (
            <div key={entry.id} style={{
              background:   'var(--bg-surface-2)',
              border:       '1px solid var(--border-primary)',
              borderRadius: 8,
              padding:      '8px 12px',
            }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 4 }}>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                  {formatDate(entry.created_at)}
                </span>
                <span style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)', fontWeight: 600 }}>
                  {entry.changed_by_profile?.full_name || '—'}
                </span>
              </div>
              <div style={{ display: 'flex', alignItems: 'center', gap: 8, fontSize: 'var(--text-sm)' }}>
                <span style={{ color: 'var(--text-muted)', textDecoration: 'line-through' }}>
                  {formatNumber(entry.limit_before)} ج.م
                </span>
                <span style={{ color: 'var(--text-muted)' }}>←</span>
                <span style={{ fontWeight: 700, color: '#16a34a' }}>
                  {formatNumber(entry.limit_after)} ج.م
                </span>
              </div>
              {entry.reason && (
                <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 4 }}>
                  {entry.reason}
                </div>
              )}
            </div>
          ))}
        </div>
      )}
    </div>
  )
}

// ── Tab 3: آخر 10 حركات ──────────────────────────────────────
function LedgerTab({ entries, customerId }: { entries: any[]; customerId: string }) {
  return (
    <div>
      {!entries.length ? (
        <div style={{ textAlign: 'center', padding: '24px 0', color: 'var(--text-muted)' }}>
          <div style={{ fontSize: '2rem', marginBottom: 8 }}>💰</div>
          <div style={{ fontWeight: 600 }}>لا توجد حركات مسجلة</div>
        </div>
      ) : (
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {entries.map((entry: any) => {
            const isDebit = entry.type === 'debit'
            return (
              <div key={entry.id} style={{
                background:   'var(--bg-surface-2)',
                border:       '1px solid var(--border-primary)',
                borderRadius: 8,
                padding:      '8px 12px',
                display:      'flex',
                alignItems:   'center',
                gap:          10,
              }}>
                <div style={{
                  width: 32, height: 32, borderRadius: '50%',
                  background: isDebit ? 'rgba(220,38,38,0.1)' : 'rgba(22,163,74,0.1)',
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  fontSize: '0.85rem', flexShrink: 0,
                }}>
                  {isDebit ? '↑' : '↓'}
                </div>
                <div style={{ flex: 1, minWidth: 0 }}>
                  <div style={{
                    fontSize: 'var(--text-xs)', color: 'var(--text-muted)',
                    whiteSpace: 'nowrap', overflow: 'hidden', textOverflow: 'ellipsis',
                  }}>
                    {entry.description || entry.source_type || '—'}
                  </div>
                  <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginTop: 2 }}>
                    {formatDate(entry.created_at)}
                  </div>
                </div>
                <div style={{ textAlign: 'end' }}>
                  <div style={{
                    fontWeight: 700,
                    fontSize:  'var(--text-sm)',
                    color:     isDebit ? '#dc2626' : '#16a34a',
                  }}>
                    {isDebit ? '+' : '-'}{formatNumber(entry.amount)}
                  </div>
                </div>
              </div>
            )
          })}
        </div>
      )}

      <a
        href={`/customers/${customerId}`}
        style={{
          display: 'block',
          marginTop: 12,
          textAlign: 'center',
          padding: '8px',
          border: '1px solid var(--border-primary)',
          borderRadius: 8,
          color: 'var(--color-primary)',
          fontSize: 'var(--text-xs)',
          fontWeight: 600,
          fontFamily: 'var(--font-sans)',
          textDecoration: 'none',
          background: 'var(--bg-surface-2)',
        }}
      >
        عرض كل الحركات ←
      </a>
    </div>
  )
}

// ── Tab 4: تعديل البنود ──────────────────────────────────────
function EditTab({
  editForm, setEditForm,
  currentBalance,
  isCashConvert, isLimitBelow,
  saving, onSave, onCancel,
}: {
  editForm:       { payment_terms: string; credit_limit: number; credit_days: number }
  setEditForm:    (f: any) => void
  currentBalance: number
  isCashConvert:  boolean
  isLimitBelow:   boolean
  saving:         boolean
  onSave:         () => void
  onCancel:       () => void
}) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 16 }}>
      {/* طريقة الدفع */}
      <div>
        <label style={{ display: 'block', fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
          طريقة الدفع
        </label>
        <select
          id="edit-payment-terms"
          value={editForm.payment_terms}
          onChange={e => setEditForm({ ...editForm, payment_terms: e.target.value })}
          className="form-input"
          style={{ width: '100%' }}
        >
          <option value="cash">نقدي</option>
          <option value="credit">آجل</option>
          <option value="mixed">مختلط</option>
        </select>

        {isCashConvert && (
          <div style={{
            marginTop: 8,
            padding: '8px 10px',
            background: 'rgba(217,119,6,0.08)',
            border: '1px solid rgba(217,119,6,0.2)',
            borderRadius: 6,
            fontSize: 'var(--text-xs)',
            color: '#92400e',
          }}>
            ℹ️ سيتحول العميل إلى نقدي — الحد الائتماني سيبقى محفوظاً لكنه لن يُطبَّق
          </div>
        )}
      </div>

      {/* الحد الائتماني */}
      <div>
        <label style={{ display: 'block', fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
          الحد الائتماني (ج.م)
        </label>
        <input
          id="edit-credit-limit"
          type="number"
          min="0"
          dir="ltr"
          value={editForm.credit_limit}
          onChange={e => setEditForm({ ...editForm, credit_limit: parseFloat(e.target.value) || 0 })}
          className="form-input"
          style={{ width: '100%', textAlign: 'end' }}
        />

        {isLimitBelow && (
          <div style={{
            marginTop: 8,
            padding: '8px 10px',
            background: 'rgba(220,38,38,0.08)',
            border: '1px solid rgba(220,38,38,0.2)',
            borderRadius: 6,
            fontSize: 'var(--text-xs)',
            color: '#991b1b',
          }}>
            ⚠️ الحد الجديد ({formatNumber(editForm.credit_limit)} ج.م) أقل من الرصيد الحالي ({formatNumber(currentBalance)} ج.م)
            — سيُعدّ العميل متجاوزاً للحد فوراً
          </div>
        )}
      </div>

      {/* مدة السداد */}
      <div>
        <label style={{ display: 'block', fontSize: 'var(--text-xs)', fontWeight: 600, color: 'var(--text-secondary)', marginBottom: 6 }}>
          مدة السداد (يوم)
        </label>
        <input
          id="edit-credit-days"
          type="number"
          min="0"
          dir="ltr"
          value={editForm.credit_days}
          onChange={e => setEditForm({ ...editForm, credit_days: parseInt(e.target.value) || 0 })}
          className="form-input"
          style={{ width: '100%', textAlign: 'end' }}
        />
      </div>

      {/* أزرار */}
      <div style={{ display: 'flex', gap: 8, marginTop: 8 }}>
        <button
          id="edit-save-btn"
          onClick={onSave}
          disabled={saving}
          style={{
            flex: 2,
            padding: '10px',
            background: saving ? 'var(--text-muted)' : 'var(--color-primary)',
            border: 'none',
            borderRadius: 8,
            color: '#fff',
            fontFamily: 'var(--font-sans)',
            fontSize: 'var(--text-sm)',
            fontWeight: 700,
            cursor: saving ? 'not-allowed' : 'pointer',
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
          }}
        >
          {saving ? '⏳ جاري الحفظ...' : '💾 حفظ التعديل'}
        </button>
        <button
          id="edit-cancel-btn"
          onClick={onCancel}
          disabled={saving}
          style={{
            flex: 1,
            padding: '10px',
            background: 'var(--bg-surface-2)',
            border: '1px solid var(--border-primary)',
            borderRadius: 8,
            color: 'var(--text-primary)',
            fontFamily: 'var(--font-sans)',
            fontSize: 'var(--text-sm)',
            fontWeight: 600,
            cursor: 'pointer',
          }}
        >
          إلغاء
        </button>
      </div>
    </div>
  )
}

// ─────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────

function translatePaymentTerms(terms: string): string {
  const map: Record<string, string> = {
    cash:   'نقدي',
    credit: 'آجل',
    mixed:  'مختلط',
  }
  return map[terms] || terms
}
