import { useState, useEffect, type ReactNode } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { toast } from 'sonner'
import {
  ArrowRight, Edit, Phone, Mail, Building, CreditCard, Users,
  Clock, FileText, Globe, Wallet, Calendar, Bell, AlertTriangle,
  Truck, Plus, Receipt, Banknote, CheckCircle, ChevronLeft,
} from 'lucide-react'
import {
  getSupplier, getSupplierContacts, getPaymentReminders,
} from '@/lib/services/suppliers'
import {
  getSupplierPayments, createSupplierPayment,
  type SupplierPaymentVoucher, type SupplierPaymentMethod,
} from '@/lib/services/supplier-payments'
import { getVaults } from '@/lib/services/vaults'
import { useAuthStore } from '@/stores/auth-store'
import type { Supplier, SupplierContact, SupplierPaymentReminder } from '@/lib/types/master-data'
import ResponsiveModal from '@/components/ui/ResponsiveModal'
import Button from '@/components/ui/Button'
import { DocumentActions } from '@/features/output/components/DocumentActions'

// ─── Helpers ─────────────────────────────────────────────────────────────────

const fmt = (n: number) =>
  n.toLocaleString('ar-EG-u-nu-latn', { minimumFractionDigits: 2, maximumFractionDigits: 2 })

const METHOD_LABELS: Record<SupplierPaymentMethod, string> = {
  cash:          '💵 نقدي',
  bank_transfer: '🏦 تحويل بنكي',
  cheque:        '📝 شيك',
  mobile_wallet: '📱 محفظة',
}

// ─── Sub-components ───────────────────────────────────────────────────────────

function InfoItem({ icon: Icon, label, value, dir }: {
  icon: any; label: string; value?: ReactNode; dir?: string
}) {
  return (
    <div style={{
      display: 'flex', alignItems: 'flex-start', gap: 'var(--space-3)',
      padding: 'var(--space-3) 0', borderBottom: '1px solid var(--border-secondary)',
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 'var(--radius-md)',
        background: 'var(--bg-surface-2)', display: 'flex', alignItems: 'center',
        justifyContent: 'center', flexShrink: 0,
      }}>
        <Icon size={14} style={{ color: 'var(--color-primary)' }} />
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 2 }}>{label}</div>
        <div style={{
          fontSize: 'var(--text-sm)', fontWeight: 500,
          color: value != null && value !== '' ? 'var(--text-primary)' : 'var(--text-muted)',
        }} dir={dir}>{value ?? '—'}</div>
      </div>
    </div>
  )
}

// ─── Pay Modal ────────────────────────────────────────────────────────────────

interface PayModalProps {
  open: boolean
  onClose: () => void
  supplierId: string
  supplierName: string
  currentBalance: number
  onSuccess: () => void
}

function SupplierPayModal({ open, onClose, supplierId, supplierName, currentBalance, onSuccess }: PayModalProps) {
  const [amount, setAmount]   = useState('')
  const [method, setMethod]   = useState<SupplierPaymentMethod>('cash')
  const [vaultId, setVaultId] = useState('')
  const [notes, setNotes]     = useState('')
  const [date, setDate]       = useState(new Date().toISOString().slice(0, 10))
  const [vaults, setVaults]   = useState<{ id: string; name: string; type: string; current_balance: number }[]>([])
  const [submitting, setSubmitting] = useState(false)

  // Load vaults once modal opens
  useEffect(() => {
    if (!open) return
    getVaults({ isActive: true })
      .then(vaultList => {
        setVaults(vaultList)
        if (vaultList[0]) setVaultId(vaultList[0].id)
      })
      .catch(() => {})
  }, [open])

  const outstanding = Math.max(0, currentBalance)
  const parsedAmt   = parseFloat(amount) || 0

  const handleSubmit = async () => {
    if (!parsedAmt || parsedAmt <= 0) { toast.error('المبلغ يجب أن يكون أكبر من صفر'); return }
    if (method !== 'cheque' && !vaultId) { toast.error('يرجى اختيار الخزينة'); return }
    setSubmitting(true)
    try {
      await createSupplierPayment({
        supplierId,
        amount: parsedAmt,
        paymentMethod: method,
        vaultId: method !== 'cheque' ? vaultId : null,
        notes: notes || null,
        paymentDate: date,
      })
      toast.success('✅ تم تسجيل الدفعة والقيود المحاسبية بنجاح')
      setAmount(''); setNotes('')
      onClose()
      onSuccess()
    } catch (err: any) {
      toast.error(err.message || 'فشلت عملية السداد')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <ResponsiveModal
      open={open}
      onClose={onClose}
      title={`دفعة للمورد — ${supplierName}`}
      size="sm"
      footer={
        <div style={{ display: 'flex', gap: 'var(--space-3)', width: '100%' }}>
          <Button variant="ghost" onClick={onClose}>إلغاء</Button>
          <Button onClick={handleSubmit} loading={submitting} icon={<Receipt size={16} />}>
            تأكيد السداد
          </Button>
        </div>
      }
    >
      <div style={{ display: 'flex', flexDirection: 'column', gap: 'var(--space-4)' }}>

        {/* رصيد المورد */}
        <div style={{
          display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 8,
          padding: '12px 14px', borderRadius: 'var(--radius-md)',
          background: 'var(--bg-surface-2)', border: '1px solid var(--border-color)',
        }}>
          <div>
            <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginBottom: 2 }}>إجمالي المستحق للمورد</div>
            <div style={{
              fontWeight: 800, fontVariantNumeric: 'tabular-nums',
              color: outstanding > 0 ? 'var(--color-danger)' : 'var(--color-success)',
            }}>
              {fmt(outstanding)} ج.م
            </div>
          </div>
          <div>
            <div style={{ fontSize: '0.7rem', color: 'var(--text-muted)', marginBottom: 2 }}>بعد الدفعة</div>
            <div style={{
              fontWeight: 800, fontVariantNumeric: 'tabular-nums',
              color: outstanding - parsedAmt > 0 ? 'var(--color-warning)' : 'var(--color-success)',
            }}>
              {fmt(Math.max(0, outstanding - parsedAmt))} ج.م
            </div>
          </div>
        </div>

        {/* تاريخ السند */}
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label className="form-label">تاريخ السداد</label>
          <input
            className="form-input" type="date"
            value={date}
            onChange={e => setDate(e.target.value)}
          />
        </div>

        {/* المبلغ */}
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label className="form-label required">مبلغ الدفعة (ج.م)</label>
          <input
            className="form-input" type="number" min="0.01" step="0.01"
            value={amount}
            onChange={e => setAmount(e.target.value)}
            placeholder={outstanding > 0 ? fmt(outstanding) : '0.00'}
            autoFocus
          />
          {parsedAmt > 0 && parsedAmt < outstanding && (
            <div style={{
              fontSize: '0.72rem', color: 'var(--color-warning, #f59e0b)',
              marginTop: 4, display: 'flex', alignItems: 'center', gap: 4,
            }}>
              <AlertTriangle size={11} />
              سداد جزئي — سيتبقى {fmt(outstanding - parsedAmt)} ج.م
            </div>
          )}
        </div>

        {/* طريقة الدفع */}
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label className="form-label required">طريقة الدفع</label>
          <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
            {(Object.entries(METHOD_LABELS) as [SupplierPaymentMethod, string][]).map(([v, label]) => (
              <button
                key={v} type="button"
                onClick={() => setMethod(v)}
                style={{
                  padding: '6px 12px', borderRadius: 8, fontSize: '0.82rem',
                  cursor: 'pointer', fontWeight: method === v ? 700 : 400,
                  background:  method === v ? 'var(--color-primary)' : 'var(--bg-surface-2)',
                  color:       method === v ? '#fff' : 'var(--text-secondary)',
                  border:      method === v ? '2px solid var(--color-primary)' : '2px solid var(--border-color)',
                  transition: 'all 0.15s',
                }}
              >
                {label}
              </button>
            ))}
          </div>
        </div>

        {/* الخزينة */}
        {method !== 'cheque' && (
          <div className="form-group" style={{ marginBottom: 0 }}>
            <label className="form-label required">الخزينة / البنك</label>
            <select className="form-select" value={vaultId} onChange={e => setVaultId(e.target.value)}>
              <option value="">— اختر الخزينة —</option>
              {vaults.map(v => (
                <option key={v.id} value={v.id}>
                  {v.name} — {fmt(v.current_balance)} ج.م
                </option>
              ))}
            </select>
          </div>
        )}

        {method === 'cheque' && (
          <div style={{
            padding: '10px 14px', borderRadius: 'var(--radius-md)',
            background: 'rgba(107,114,128,0.08)', fontSize: '0.8rem',
            color: 'var(--text-muted)', display: 'flex', gap: 8, alignItems: 'center',
          }}>
            <Banknote size={14} />
            سيُسجَّل في حساب أوراق الدفع (2110) — لا تُخصم من الخزينة الآن.
          </div>
        )}

        {/* ملاحظات */}
        <div className="form-group" style={{ marginBottom: 0 }}>
          <label className="form-label">ملاحظات (اختياري)</label>
          <input
            className="form-input" value={notes}
            onChange={e => setNotes(e.target.value)}
            placeholder="مرجع التحويل، رقم الشيك، وصف الدفعة..."
          />
        </div>

      </div>
    </ResponsiveModal>
  )
}

// ─── Payments Tab ─────────────────────────────────────────────────────────────

function PaymentsTab({ supplierId, supplierName, currentBalance, refreshSupplier }: {
  supplierId: string
  supplierName: string
  currentBalance: number
  refreshSupplier: () => void
}) {
  const can = useAuthStore(s => s.can)
  const [vouchers, setVouchers]   = useState<SupplierPaymentVoucher[]>([])
  const [loading, setLoading]     = useState(true)
  const [payOpen, setPayOpen]     = useState(false)
  const [total, setTotal]         = useState(0)

  const load = async () => {
    setLoading(true)
    try {
      const res = await getSupplierPayments({ supplierId, pageSize: 50 })
      setVouchers(res.data)
      setTotal(res.data.reduce((s, v) => s + v.amount, 0))
    } catch { toast.error('فشل تحميل سجل الدفعات') }
    finally { setLoading(false) }
  }

  useEffect(() => { load() }, [supplierId])

  const outstanding = Math.max(0, currentBalance)

  return (
    <div style={{ padding: '0 12px' }}>

      {/* Summary + Action Bar */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(150px, 1fr))',
        gap: 12, marginBottom: 'var(--space-4)',
      }}>
        <div className="stat-card">
          <div className="stat-card-label">إجمالي المستحق</div>
          <div className="stat-card-value" style={{
            color: outstanding > 0 ? 'var(--color-danger)' : 'var(--color-success)',
            fontSize: 'var(--text-xl)',
          }}>
            {fmt(outstanding)}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">إجمالي ما سُدِّد</div>
          <div className="stat-card-value" style={{ color: 'var(--color-success)', fontSize: 'var(--text-xl)' }}>
            {fmt(total)}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">عدد الدفعات</div>
          <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)' }}>
            {vouchers.length}
          </div>
        </div>
      </div>

      {/* Guard: show pay button only if user can pay and balance > 0 */}
      {can('procurement.invoices.pay') && outstanding > 0 && (
        <div style={{ marginBottom: 'var(--space-4)' }}>
          <Button
            icon={<Plus size={16} />}
            onClick={() => setPayOpen(true)}
          >
            دفعة جديدة للمورد
          </Button>
        </div>
      )}

      {/* Table */}
      <div className="edara-card" style={{ overflow: 'auto' }}>
        {loading ? (
          <div style={{ padding: 40, textAlign: 'center' }}>
            {[1, 2, 3].map(i => (
              <div key={i} className="skeleton skeleton-row" style={{ marginBottom: 8 }} />
            ))}
          </div>
        ) : vouchers.length === 0 ? (
          <div style={{ padding: 48, textAlign: 'center' }}>
            <Receipt size={40} style={{ color: 'var(--text-muted)', opacity: 0.3, margin: '0 auto 12px', display: 'block' }} />
            <div style={{ color: 'var(--text-muted)', fontSize: 'var(--text-sm)' }}>
              لا توجد دفعات مسجلة لهذا المورد
            </div>
            {can('procurement.invoices.pay') && outstanding > 0 && (
              <button
                onClick={() => setPayOpen(true)}
                style={{
                  marginTop: 16, padding: '8px 18px', borderRadius: 'var(--radius-md)',
                  background: 'var(--color-primary)', color: '#fff', border: 'none',
                  cursor: 'pointer', fontWeight: 600, fontSize: 'var(--text-sm)',
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                }}
              >
                <Plus size={14} /> سجل أول دفعة
              </button>
            )}
          </div>
        ) : (
          <table className="data-table">
            <thead>
              <tr>
                <th>رقم السند</th>
                <th>التاريخ</th>
                <th>المبلغ</th>
                <th className="hide-mobile">طريقة الدفع</th>
                <th className="hide-mobile">الخزينة</th>
                <th className="hide-mobile">ملاحظات</th>
                <th>الحالة</th>
                <th style={{ width: 100 }}></th>
              </tr>
            </thead>
            <tbody>
              {vouchers.map(v => (
                <tr key={v.id}>
                  <td style={{ fontFamily: 'monospace', fontSize: 'var(--text-xs)', fontWeight: 600 }}>
                    {v.number}
                  </td>
                  <td style={{ fontSize: 'var(--text-xs)', whiteSpace: 'nowrap' }}>
                    {new Date(v.payment_date).toLocaleDateString('ar-EG-u-nu-latn')}
                  </td>
                  <td style={{ fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: 'var(--color-success)' }}>
                    {fmt(v.amount)} ج.م
                  </td>
                  <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>
                    {METHOD_LABELS[v.payment_method] || v.payment_method}
                  </td>
                  <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>
                    {v.vault?.name || (v.payment_method === 'cheque' ? 'أوراق دفع (2110)' : '—')}
                  </td>
                  <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)' }}>
                    {v.notes || '—'}
                  </td>
                  <td>
                    <span className={`badge ${v.status === 'posted' ? 'badge-success' : 'badge-danger'}`}>
                      {v.status === 'posted' ? (
                        <><CheckCircle size={10} style={{ display: 'inline', marginLeft: 3 }} />مُرحَّل</>
                      ) : 'مُعكوس'}
                    </span>
                  </td>
                  <td style={{ textAlign: 'left' }}>
                    <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
                      <DocumentActions kind="payment-voucher" entityId={v.id} />
                    </div>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        )}
      </div>

      {/* Pay Modal */}
      <SupplierPayModal
        open={payOpen}
        onClose={() => setPayOpen(false)}
        supplierId={supplierId}
        supplierName={supplierName}
        currentBalance={currentBalance}
        onSuccess={() => { load(); refreshSupplier() }}
      />
    </div>
  )
}

// ─── Main Page ────────────────────────────────────────────────────────────────

export default function SupplierDetailPage() {
  const { id } = useParams()
  const navigate = useNavigate()
  const can = useAuthStore(s => s.can)

  const [loading, setLoading] = useState(true)
  const [supplier, setSupplier] = useState<Supplier | null>(null)
  const [tab, setTab] = useState<'info' | 'contacts' | 'reminders' | 'payments'>('info')
  const [contacts, setContacts] = useState<SupplierContact[]>([])
  const [reminders, setReminders] = useState<SupplierPaymentReminder[]>([])

  const loadSupplier = async () => {
    if (!id) return
    try {
      const [s, ct, rm] = await Promise.all([
        getSupplier(id),
        getSupplierContacts(id),
        getPaymentReminders({ supplierId: id }).then(r => r.data),
      ])
      setSupplier(s)
      setContacts(ct)
      setReminders(rm)
    } catch { toast.error('فشل تحميل بيانات المورد') }
    finally { setLoading(false) }
  }

  useEffect(() => { loadSupplier() }, [id])

  const paymentLabels: Record<string, string> = { cash: 'نقدي', credit: 'آجل', mixed: 'مختلط' }
  const paymentBadge: Record<string, string>  = { cash: 'badge-success', credit: 'badge-warning', mixed: 'badge-neutral' }
  const statusLabels: Record<string, { label: string; cls: string }> = {
    pending: { label: 'معلق',   cls: 'badge-warning' },
    paid:    { label: 'مدفوع',  cls: 'badge-success' },
    overdue: { label: 'متأخر',  cls: 'badge-danger'  },
  }

  if (loading) return (
    <div className="page-container animate-enter">
      {[1, 2, 3, 4].map(i => (
        <div key={i} className="skeleton skeleton-row" style={{ margin: 'var(--space-4) 0' }} />
      ))}
    </div>
  )

  if (!supplier) return (
    <div className="page-container animate-enter">
      <div className="empty-state">
        <Truck size={48} className="empty-state-icon" />
        <p className="empty-state-title">المورد غير موجود</p>
        <button className="btn btn-primary" onClick={() => navigate('/suppliers')}>العودة للموردين</button>
      </div>
    </div>
  )

  const balance = supplier.current_balance ?? 0

  return (
    <div style={{ maxWidth: 900, margin: '0 auto', paddingBottom: 80 }}>

      {/* ══ Sticky Header ══ */}
      <div style={{
        position: 'sticky', top: 0, zIndex: 10,
        background: 'var(--bg-surface)',
        borderBottom: '1px solid var(--border-primary)',
        backdropFilter: 'blur(12px)',
        padding: '14px 16px',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
          <button
            onClick={() => navigate('/suppliers')}
            style={{
              background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)',
              borderRadius: 10, padding: '7px 10px', cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: 4,
              fontSize: 13, color: 'var(--text-secondary)', flexShrink: 0,
            }}
          >
            <ArrowRight size={14} /> رجوع
          </button>
          <div style={{ flex: 1, minWidth: 0 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 17, fontWeight: 800, margin: 0, overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap' }}>
                {supplier.name}
              </h1>
              <span className={`badge ${paymentBadge[supplier.payment_terms || 'cash'] || 'badge-neutral'}`}>
                {paymentLabels[supplier.payment_terms || 'cash'] || supplier.payment_terms}
              </span>
              <span className={`badge ${supplier.is_active ? 'badge-success' : 'badge-danger'}`}>
                {supplier.is_active ? 'نشط' : 'معطل'}
              </span>
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2, fontFamily: 'monospace', direction: 'ltr', display: 'inline-block' }}>
              {supplier.code}
            </div>
          </div>

          {/* Quick Pay button in header (if balance > 0) */}
          {can('procurement.invoices.pay') && balance > 0 && tab !== 'payments' && (
            <button
              onClick={() => setTab('payments')}
              style={{
                background: 'rgba(239,68,68,0.1)', color: 'var(--color-danger)',
                border: '1.5px solid rgba(239,68,68,0.25)', borderRadius: 10,
                padding: '7px 12px', cursor: 'pointer', display: 'flex',
                alignItems: 'center', gap: 5, fontSize: 12, fontWeight: 700, flexShrink: 0,
              }}
            >
              <Receipt size={13} /> سداد
              <span style={{
                background: 'var(--color-danger)', color: '#fff', borderRadius: 99,
                padding: '1px 6px', fontSize: 10, fontWeight: 800,
              }}>
                {fmt(balance)}
              </span>
            </button>
          )}

          {can('suppliers.update') && (
            <button
              onClick={() => navigate(`/suppliers/${id}/edit`)}
              style={{
                background: 'var(--color-primary)', color: '#fff', border: 'none',
                borderRadius: 10, padding: '8px 14px', cursor: 'pointer',
                display: 'flex', alignItems: 'center', gap: 5,
                fontSize: 13, fontWeight: 600, flexShrink: 0,
              }}
            >
              <Edit size={14} /> تعديل
            </button>
          )}
        </div>
      </div>

      {/* Stats Row */}
      <div style={{
        display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(140px, 1fr))',
        gap: 'var(--space-3)', margin: '0 12px var(--space-4)',
      }}>
        <div className="stat-card">
          <div className="stat-card-label">طريقة الدفع</div>
          <span className={`badge ${paymentBadge[supplier.payment_terms || 'cash'] || 'badge-neutral'}`} style={{ alignSelf: 'flex-start' }}>
            {paymentLabels[supplier.payment_terms || 'cash'] || supplier.payment_terms}
          </span>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">حد الائتمان</div>
          <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)' }}>
            {supplier.credit_limit > 0 ? supplier.credit_limit.toLocaleString('ar-EG-u-nu-latn') : '—'}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الرصيد الافتتاحي</div>
          <div className="stat-card-value" style={{ fontSize: 'var(--text-xl)', color: 'var(--text-secondary)' }}>
            {fmt(supplier.opening_balance ?? 0)}
          </div>
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الرصيد الحالي</div>
          <div className="stat-card-value" style={{
            fontSize: 'var(--text-xl)',
            color: balance > 0 ? 'var(--color-danger)' : balance < 0 ? 'var(--color-primary)' : 'var(--color-success)',
            fontWeight: 700,
          }}>
            {fmt(balance)}
          </div>
          {balance > 0 && (
            <div style={{ fontSize: '0.65rem', color: 'var(--color-danger)', marginTop: 2, opacity: 0.85 }}>
              مستحق للمورد
            </div>
          )}
        </div>
        <div className="stat-card">
          <div className="stat-card-label">الحالة</div>
          <span className={`badge ${supplier.is_active ? 'badge-success' : 'badge-danger'}`} style={{ alignSelf: 'flex-start' }}>
            {supplier.is_active ? 'نشط' : 'معطل'}
          </span>
        </div>
      </div>

      {/* Tabs */}
      <div className="tabs" style={{ overflowX: 'auto', scrollbarWidth: 'none', flexWrap: 'nowrap', padding: '0 12px' }}>
        <button className={`tab ${tab === 'info' ? 'active' : ''}`} onClick={() => setTab('info')}>
          <Building size={14} /> المعلومات
        </button>
        <button className={`tab ${tab === 'contacts' ? 'active' : ''}`} onClick={() => setTab('contacts')}>
          <Users size={14} /> جهات الاتصال
          {contacts.length > 0 && (
            <span className="badge badge-neutral" style={{ marginRight: 'var(--space-1)' }}>{contacts.length}</span>
          )}
        </button>
        <button className={`tab ${tab === 'reminders' ? 'active' : ''}`} onClick={() => setTab('reminders')}>
          <Bell size={14} /> تذكيرات
          {reminders.length > 0 && (
            <span className="badge badge-warning" style={{ marginRight: 'var(--space-1)' }}>{reminders.length}</span>
          )}
        </button>
        {/* Payments tab — always visible, badge if balance > 0 */}
        <button className={`tab ${tab === 'payments' ? 'active' : ''}`} onClick={() => setTab('payments')}>
          <Receipt size={14} /> الدفعات
          {balance > 0 && (
            <span className="badge badge-danger" style={{ marginRight: 'var(--space-1)' }}>
              {fmt(balance)}
            </span>
          )}
        </button>
      </div>

      {/* ═══════ TAB: INFO ═══════ */}
      {tab === 'info' && (
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fit, minmax(240px, 1fr))', gap: 'var(--space-4)', padding: '0 12px' }}>
          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Phone size={16} style={{ color: 'var(--color-primary)' }} /> بيانات الاتصال
            </h3>
            {supplier.phone ? (
              <InfoItem icon={Phone} label="الهاتف" dir="ltr"
                value={<a href={`tel:${supplier.phone}`} style={{ color: 'var(--color-primary)', textDecoration: 'none', fontFamily: 'monospace' }}>{supplier.phone}</a>} />
            ) : (
              <InfoItem icon={Phone} label="الهاتف" value="—" />
            )}
            <InfoItem icon={Mail} label="البريد" value={supplier.email} dir="ltr" />
            <InfoItem icon={FileText} label="الرقم الضريبي" value={supplier.tax_number} dir="ltr" />
            <InfoItem icon={Building} label="النوع" value={supplier.type} />
          </div>

          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Globe size={16} style={{ color: 'var(--color-primary)' }} /> العنوان
            </h3>
            <InfoItem icon={Globe} label="المحافظة" value={supplier.governorate?.name} />
            <InfoItem icon={Building} label="المدينة" value={supplier.city?.name} />
          </div>

          <div className="edara-card" style={{ padding: 'var(--space-5)' }}>
            <h3 style={{ fontSize: 'var(--text-base)', fontWeight: 700, marginBottom: 'var(--space-3)', display: 'flex', alignItems: 'center', gap: 'var(--space-2)' }}>
              <Wallet size={16} style={{ color: 'var(--color-primary)' }} /> البيانات المالية
            </h3>
            <InfoItem icon={CreditCard} label="حد الائتمان" value={supplier.credit_limit > 0 ? supplier.credit_limit.toLocaleString('ar-EG-u-nu-latn') : '—'} />
            <InfoItem icon={Calendar} label="أيام السداد" value={supplier.credit_days > 0 ? `${supplier.credit_days} يوم` : '—'} />
            <InfoItem icon={Wallet} label="الرصيد الافتتاحي" value={fmt(supplier.opening_balance ?? 0)} />
            <InfoItem icon={Wallet} label="الرصيد الحالي"
              value={
                <span style={{ fontWeight: 700, color: balance > 0 ? 'var(--color-danger)' : balance < 0 ? 'var(--color-primary)' : 'var(--color-success)' }}>
                  {fmt(balance)}
                </span>
              } />
            <InfoItem icon={CreditCard} label="الحساب البنكي" value={supplier.bank_account} dir="ltr" />
          </div>
        </div>
      )}

      {/* ═══════ TAB: CONTACTS ═══════ */}
      {tab === 'contacts' && (
        <div className="edara-card" style={{ padding: 'var(--space-5)', margin: '0 12px' }}>
          <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>جهات الاتصال</h3>
          {contacts.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد جهات اتصال</p>
          ) : (
            <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(260px, 1fr))', gap: 'var(--space-3)' }}>
              {contacts.map(c => (
                <div key={c.id} style={{
                  background: 'var(--bg-surface-2)', borderRadius: 'var(--radius-md)',
                  padding: 'var(--space-4)', border: '1px solid var(--border-secondary)',
                }}>
                  <div style={{ fontWeight: 700, fontSize: 'var(--text-sm)', marginBottom: 'var(--space-2)' }}>{c.name}</div>
                  {c.role && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-muted)', marginBottom: 'var(--space-1)' }}>{c.role}</div>}
                  {c.phone && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }} dir="ltr"><Phone size={10} style={{ display: 'inline' }} /> {c.phone}</div>}
                  {c.email && <div style={{ fontSize: 'var(--text-xs)', color: 'var(--text-secondary)' }} dir="ltr"><Mail size={10} style={{ display: 'inline' }} /> {c.email}</div>}
                </div>
              ))}
            </div>
          )}
        </div>
      )}

      {/* ═══════ TAB: REMINDERS ═══════ */}
      {tab === 'reminders' && (
        <div className="edara-card" style={{ overflow: 'auto', margin: '0 12px' }}>
          <div style={{ padding: 'var(--space-5) var(--space-5) 0' }}>
            <h3 style={{ fontSize: 'var(--text-lg)', fontWeight: 700, marginBottom: 'var(--space-4)' }}>تذكيرات السداد</h3>
          </div>
          {reminders.length === 0 ? (
            <p style={{ textAlign: 'center', color: 'var(--text-muted)', padding: 'var(--space-6)' }}>لا يوجد تذكيرات</p>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>تاريخ الاستحقاق</th>
                  <th>المبلغ</th>
                  <th className="hide-mobile">مرجع الفاتورة</th>
                  <th>الحالة</th>
                </tr>
              </thead>
              <tbody>
                {reminders.map(r => (
                  <tr key={r.id}>
                    <td style={{ fontSize: 'var(--text-xs)' }}>{new Date(r.due_date).toLocaleDateString('ar-EG-u-nu-latn')}</td>
                    <td style={{ fontWeight: 600 }}>{r.amount.toLocaleString('ar-EG-u-nu-latn')}</td>
                    <td className="hide-mobile" style={{ fontSize: 'var(--text-xs)' }}>{r.invoice_ref || '—'}</td>
                    <td><span className={`badge ${statusLabels[r.status]?.cls || 'badge-neutral'}`}>{statusLabels[r.status]?.label || r.status}</span></td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </div>
      )}

      {/* ═══════ TAB: PAYMENTS ═══════ */}
      {tab === 'payments' && id && supplier && (
        <PaymentsTab
          supplierId={id}
          supplierName={supplier.name}
          currentBalance={balance}
          refreshSupplier={loadSupplier}
        />
      )}

    </div>
  )
}
