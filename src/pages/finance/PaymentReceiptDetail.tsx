import { useParams, useNavigate, Link } from 'react-router-dom'
import { useQuery } from '@tanstack/react-query'
import { toast } from 'sonner'
import {
  ArrowRight, Check, XCircle, Receipt, User, CreditCard,
  Calendar, Building2, FileText, Wallet, ExternalLink,
  ImageIcon, Clock, AlertTriangle,
} from 'lucide-react'
import { getPaymentReceipt, confirmPaymentReceipt, rejectPaymentReceipt } from '@/lib/services/payments'
import { useVaults, useInvalidate } from '@/hooks/useQueryHooks'
import { useAuthStore } from '@/stores/auth-store'
import { formatCurrency, formatDateTime } from '@/lib/utils/format'
import Button from '@/components/ui/Button'
import Modal from '@/components/ui/Modal'
import Badge from '@/components/ui/Badge'
import { useState } from 'react'

// ══════════════════════════════════════════════════════════════
// Config
// ══════════════════════════════════════════════════════════════

const METHOD_LABEL: Record<string, string> = {
  cash: 'نقدي', bank_transfer: 'تحويل بنكي',
  instapay: 'إنستاباي', cheque: 'شيك بنكي', mobile_wallet: 'محفظة إلكترونية',
}
const METHOD_ICON: Record<string, string> = {
  cash: '💵', bank_transfer: '🏦', instapay: '⚡', cheque: '📋', mobile_wallet: '📱',
}
const STATUS_CONFIG: Record<string, { label: string; variant: 'warning' | 'success' | 'danger' }> = {
  pending:   { label: 'معلق — بانتظار المراجعة', variant: 'warning' },
  confirmed: { label: 'مؤكد',                    variant: 'success' },
  rejected:  { label: 'مرفوض',                   variant: 'danger'  },
}

// ══════════════════════════════════════════════════════════════
// Sub-components
// ══════════════════════════════════════════════════════════════

const card: React.CSSProperties = {
  background: 'var(--bg-surface)',
  border: '1px solid var(--border-primary)',
  borderRadius: 12,
  padding: 16,
  marginBottom: 12,
}

function SectionHead({ icon, title }: { icon: React.ReactNode; title: string }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 14 }}>
      <span style={{
        width: 28, height: 28, borderRadius: 8,
        background: 'var(--bg-surface-2)', color: 'var(--color-primary)',
        display: 'flex', alignItems: 'center', justifyContent: 'center', flexShrink: 0,
      }}>{icon}</span>
      <span style={{ fontWeight: 700, fontSize: 13 }}>{title}</span>
    </div>
  )
}

function InfoRow({ label, value, mono }: { label: string; value: React.ReactNode; mono?: boolean }) {
  return (
    <div style={{
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      padding: '8px 0',
      borderBottom: '1px solid var(--border-primary)',
    }}>
      <span style={{ fontSize: 12, color: 'var(--text-muted)' }}>{label}</span>
      <span style={{
        fontSize: 13, fontWeight: 600, color: 'var(--text-primary)',
        fontFamily: mono ? 'monospace' : 'inherit',
        direction: mono ? 'ltr' : 'inherit',
      }}>
        {value || '—'}
      </span>
    </div>
  )
}

// ══════════════════════════════════════════════════════════════
// Main
// ══════════════════════════════════════════════════════════════

export default function PaymentReceiptDetail() {
  const { id } = useParams<{ id: string }>()
  const navigate = useNavigate()
  const can      = useAuthStore(s => s.can)
  const invalidate = useInvalidate()

  const { data: receipt, isLoading, refetch } = useQuery({
    queryKey: ['payment-receipt', id],
    queryFn: () => getPaymentReceipt(id!),
    enabled: !!id,
    staleTime: 30_000,
  })

  const { data: vaults = [] } = useVaults({ isActive: true })

  // ── Confirm ──
  const [confirmOpen, setConfirmOpen]   = useState(false)
  const [confirmVaultId, setConfirmVaultId] = useState('')
  const [confirming, setConfirming]     = useState(false)

  const methodConfig = receipt
    ? { vaultType: receipt.payment_method === 'cash' ? 'cash' : receipt.payment_method === 'bank_transfer' ? 'bank' : receipt.payment_method === 'cheque' ? null : 'mobile_wallet' }
    : null
  const isCheque       = receipt?.payment_method === 'cheque'
  const hasCustodyLink = !!receipt?.custody_id
  const filteredVaults = vaults.filter(v => !methodConfig?.vaultType || v.type === (methodConfig.vaultType as any))

  const openConfirm = () => {
    const first = filteredVaults[0]
    setConfirmVaultId(first?.id || '')
    setConfirmOpen(true)
  }

  const handleConfirm = async () => {
    if (!receipt) return
    if (!isCheque && !hasCustodyLink && !confirmVaultId) {
      toast.error('يرجى اختيار وجهة المبلغ'); return
    }
    setConfirming(true)
    try {
      await confirmPaymentReceipt(receipt.id, (isCheque || hasCustodyLink) ? null : confirmVaultId)
      toast.success('تم تأكيد الإيصال بنجاح')
      setConfirmOpen(false)
      invalidate('payment-receipts', 'payment-receipt')
      await refetch()
    } catch (e: any) {
      toast.error(e.message || 'فشل التأكيد')
    } finally {
      setConfirming(false)
    }
  }

  // ── Reject ──
  const [rejectOpen, setRejectOpen]   = useState(false)
  const [rejectReason, setRejectReason] = useState('')
  const [rejecting, setRejecting]     = useState(false)

  const handleReject = async () => {
    if (!receipt || !rejectReason.trim()) { toast.error('سبب الرفض مطلوب'); return }
    setRejecting(true)
    try {
      await rejectPaymentReceipt(receipt.id, rejectReason)
      toast.success('تم رفض الإيصال')
      setRejectOpen(false)
      invalidate('payment-receipts', 'payment-receipt')
      await refetch()
    } catch (e: any) {
      toast.error(e.message || 'فشل الرفض')
    } finally {
      setRejecting(false)
    }
  }

  // ── Loading / Not Found ──
  if (isLoading) return (
    <div style={{ maxWidth: 640, margin: '0 auto', padding: 16 }}>
      {[1,2,3].map(i => <div key={i} className="skeleton" style={{ height: i === 1 ? 80 : 140, marginBottom: 12, borderRadius: 12 }} />)}
    </div>
  )

  if (!receipt) return (
    <div style={{ padding: 24, textAlign: 'center', color: 'var(--text-muted)' }}>
      الإيصال غير موجود
    </div>
  )

  const sc = STATUS_CONFIG[receipt.status]
  const isProofImage = receipt.proof_url && /\.(jpg|jpeg|png|gif|webp)$/i.test(receipt.proof_url)
  const isProofPdf   = receipt.proof_url && /\.pdf$/i.test(receipt.proof_url)

  return (
    <div style={{ maxWidth: 640, margin: '0 auto', padding: '0 0 80px' }}>

      {/* ── Hero Header ── */}
      <div style={{
        background: 'var(--bg-surface)',
        borderBottom: '1px solid var(--border-primary)',
        padding: '14px 16px',
        position: 'sticky', top: 0, zIndex: 10,
        backdropFilter: 'blur(12px)',
      }}>
        <div style={{ display: 'flex', alignItems: 'center', gap: 10, marginBottom: 8 }}>
          <button onClick={() => navigate('/finance/payments')}
            style={{
              background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)',
              borderRadius: 8, padding: '6px 10px', cursor: 'pointer',
              display: 'flex', alignItems: 'center', gap: 4,
              fontSize: 12, color: 'var(--text-secondary)',
            }}>
            <ArrowRight size={13} /> رجوع
          </button>
          <div style={{ flex: 1 }}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexWrap: 'wrap' }}>
              <h1 style={{ fontSize: 17, fontWeight: 800, margin: 0, direction: 'ltr', display: 'inline-block' }}>
                {receipt.number}
              </h1>
              <Badge variant={sc?.variant}>{sc?.label}</Badge>
            </div>
            <div style={{ fontSize: 11, color: 'var(--text-muted)', marginTop: 2 }}>
              {receipt.customer?.name} • {formatDateTime(receipt.created_at)}
            </div>
          </div>
        </div>

        {/* Action buttons — pending only */}
        {receipt.status === 'pending' && can('finance.payments.confirm') && (
          <div style={{ display: 'flex', gap: 8 }}>
            <Button size="sm" onClick={openConfirm} icon={<Check size={13} />}>
              تأكيد الاستلام
            </Button>
            <Button variant="danger" size="sm" onClick={() => { setRejectReason(''); setRejectOpen(true) }}
              icon={<XCircle size={13} />}>
              رفض
            </Button>
          </div>
        )}
      </div>

      {/* ── Amount Hero ── */}
      <div style={{
        background: `linear-gradient(135deg, color-mix(in srgb, var(--color-primary) 10%, transparent), color-mix(in srgb, var(--color-primary) 4%, transparent))`,
        borderBottom: '1px solid var(--border-primary)',
        padding: '20px 16px',
        textAlign: 'center',
      }}>
        <div style={{ fontSize: 11, color: 'var(--text-muted)', marginBottom: 4 }}>المبلغ المحصَّل</div>
        <div style={{
          fontSize: 32, fontWeight: 900, color: 'var(--color-success)',
          fontVariantNumeric: 'tabular-nums', lineHeight: 1.2,
        }}>
          {formatCurrency(receipt.amount)}
        </div>
        <div style={{
          marginTop: 8, fontSize: 13, color: 'var(--text-secondary)',
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 6,
        }}>
          <span>{METHOD_ICON[receipt.payment_method] || '💳'}</span>
          <span>{METHOD_LABEL[receipt.payment_method] || receipt.payment_method}</span>
        </div>
      </div>

      <div style={{ padding: '12px 12px 0' }}>

        {/* ── بيانات الإيصال ── */}
        <div style={card}>
          <SectionHead icon={<Receipt size={14} />} title="بيانات الإيصال" />
          <InfoRow label="رقم الإيصال" value={receipt.number}  mono />
          <InfoRow label="العميل" value={
            receipt.customer ? (
              <Link to={`/customers/${receipt.customer.id}`}
                style={{ color: 'var(--color-primary)', textDecoration: 'none', display: 'flex', alignItems: 'center', gap: 4 }}>
                {receipt.customer.name}
                <ExternalLink size={11} />
              </Link>
            ) : '—'
          } />
          <InfoRow label="كود العميل" value={receipt.customer?.code} mono />
          <InfoRow label="الفاتورة المرتبطة" value={
            receipt.sales_order ? (
              <Link to={`/sales/orders/${receipt.sales_order_id}`}
                style={{ color: 'var(--color-primary)', textDecoration: 'none', display: 'flex', alignItems: 'center', gap: 4, direction: 'ltr' }}>
                {receipt.sales_order.order_number}
                <ExternalLink size={11} />
              </Link>
            ) : '—'
          } />
          <InfoRow label="تاريخ الإنشاء" value={formatDateTime(receipt.created_at)} />
          <InfoRow label="منشئ الإيصال" value={receipt.created_by_profile?.full_name} />
        </div>

        {/* ── تفاصيل الدفع ── */}
        <div style={card}>
          <SectionHead icon={<CreditCard size={14} />} title="تفاصيل الدفع" />
          <InfoRow label="طريقة الدفع"
            value={`${METHOD_ICON[receipt.payment_method] || ''} ${METHOD_LABEL[receipt.payment_method] || receipt.payment_method}`}
          />
          {receipt.bank_reference && (
            <InfoRow label="رقم المرجع" value={receipt.bank_reference} mono />
          )}
          {receipt.check_number && (
            <InfoRow label="رقم الشيك" value={receipt.check_number} mono />
          )}
          {receipt.check_date && (
            <InfoRow label="تاريخ استحقاق الشيك" value={receipt.check_date} mono />
          )}
          {receipt.vault && (
            <InfoRow label="الخزنة / الحساب" value={receipt.vault.name} />
          )}
          {receipt.custody_id && (
            <InfoRow label="عهدة ميدانية" value={
              <span style={{ display: 'flex', alignItems: 'center', gap: 4, color: 'var(--color-warning)' }}>
                <Wallet size={12} /> مرتبط بعهدة
              </span>
            } />
          )}
        </div>

        {/* ── الحالة والمراجعة ── */}
        <div style={card}>
          <SectionHead icon={<Clock size={14} />} title="حالة المراجعة" />
          <InfoRow label="الحالة الحالية" value={<Badge variant={sc?.variant}>{sc?.label}</Badge>} />
          {receipt.reviewed_by_profile && (
            <InfoRow label="مراجع بواسطة" value={receipt.reviewed_by_profile.full_name} />
          )}
          {receipt.reviewed_at && (
            <InfoRow label="تاريخ المراجعة" value={formatDateTime(receipt.reviewed_at)} />
          )}
          {receipt.rejection_reason && (
            <div style={{
              marginTop: 10, padding: '10px 12px', borderRadius: 8,
              background: 'color-mix(in srgb, var(--color-danger) 8%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-danger) 25%, transparent)',
              fontSize: 12, color: 'var(--text-secondary)',
              display: 'flex', gap: 8, alignItems: 'flex-start',
            }}>
              <AlertTriangle size={13} style={{ color: 'var(--color-danger)', flexShrink: 0, marginTop: 1 }} />
              <div>
                <div style={{ fontWeight: 700, color: 'var(--color-danger)', marginBottom: 4 }}>سبب الرفض</div>
                {receipt.rejection_reason}
              </div>
            </div>
          )}
          {receipt.notes && (
            <div style={{ marginTop: 10, fontSize: 12, color: 'var(--text-secondary)', lineHeight: 1.6 }}>
              <div style={{ fontWeight: 600, marginBottom: 4 }}>ملاحظات</div>
              {receipt.notes}
            </div>
          )}
        </div>

        {/* ── إثبات الدفع ── */}
        {receipt.proof_url ? (
          <div style={card}>
            <SectionHead icon={<ImageIcon size={14} />} title="إثبات الدفع" />
            {isProofImage ? (
              <div>
                <a href={receipt.proof_url} target="_blank" rel="noreferrer" style={{ display: 'block' }}>
                  <img
                    src={receipt.proof_url}
                    alt="إثبات الدفع"
                    style={{
                      width: '100%',
                      maxHeight: 360,
                      objectFit: 'contain',
                      borderRadius: 8,
                      border: '1px solid var(--border-primary)',
                      cursor: 'zoom-in',
                      display: 'block',
                    }}
                  />
                  <div style={{
                    marginTop: 8, fontSize: 11, color: 'var(--color-primary)',
                    display: 'flex', alignItems: 'center', gap: 4,
                  }}>
                    <ExternalLink size={11} /> فتح الصورة كاملة في نافذة جديدة
                  </div>
                </a>
              </div>
            ) : isProofPdf ? (
              <a href={receipt.proof_url} target="_blank" rel="noreferrer"
                style={{
                  display: 'inline-flex', alignItems: 'center', gap: 8,
                  padding: '10px 16px', borderRadius: 8,
                  background: 'color-mix(in srgb, var(--color-primary) 8%, transparent)',
                  border: '1px solid color-mix(in srgb, var(--color-primary) 25%, transparent)',
                  color: 'var(--color-primary)', textDecoration: 'none',
                  fontWeight: 600, fontSize: 13,
                }}>
                <FileText size={16} /> فتح ملف PDF
                <ExternalLink size={12} />
              </a>
            ) : (
              <a href={receipt.proof_url} target="_blank" rel="noreferrer"
                style={{
                  display: 'inline-flex', alignItems: 'center', gap: 6,
                  fontSize: 13, color: 'var(--color-primary)', fontWeight: 600,
                }}>
                <ExternalLink size={13} /> فتح الإثبات
              </a>
            )}
          </div>
        ) : (
          receipt.status === 'pending' && (
            <div style={{
              ...card,
              background: 'color-mix(in srgb, var(--color-warning) 6%, transparent)',
              border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)',
              display: 'flex', gap: 8, alignItems: 'flex-start', padding: '12px 14px',
            }}>
              <AlertTriangle size={14} style={{ color: 'var(--color-warning)', flexShrink: 0, marginTop: 1 }} />
              <span style={{ fontSize: 12, color: 'var(--text-secondary)' }}>
                لا يوجد إثبات دفع مرفق — تأكد من صحة التحصيل قبل تأكيد الإيصال
              </span>
            </div>
          )
        )}

        {/* ── المركز المالي ── */}
        {(receipt.branch || receipt.collected_by_profile) && (
          <div style={card}>
            <SectionHead icon={<Building2 size={14} />} title="بيانات التحصيل" />
            {receipt.branch && <InfoRow label="الفرع" value={receipt.branch.name} />}
            {receipt.collected_by_profile && (
              <InfoRow label="محصَّل بواسطة" value={receipt.collected_by_profile.full_name} />
            )}
          </div>
        )}

      </div>

      {/* ════════════════════════════════════════════════════════════ */}
      {/* ── نافذة تأكيد الإيصال ── */}
      <Modal
        open={confirmOpen}
        onClose={() => setConfirmOpen(false)}
        title="تأكيد استلام الإيصال"
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setConfirmOpen(false)} disabled={confirming}>إلغاء</Button>
            <Button onClick={handleConfirm} loading={confirming}>تأكيد الاستلام</Button>
          </>
        }
      >
        <div className="flex-col gap-3">
          <div style={{
            background: 'var(--bg-surface-2)', border: '1px solid var(--border-primary)',
            borderRadius: 10, overflow: 'hidden',
          }}>
            {[
              { label: 'العميل', value: receipt.customer?.name || '—' },
              { label: 'المبلغ',  value: formatCurrency(receipt.amount) },
              { label: 'الطريقة', value: `${METHOD_ICON[receipt.payment_method]} ${METHOD_LABEL[receipt.payment_method]}` },
            ].map((r, i, arr) => (
              <div key={i} style={{
                display: 'flex', justifyContent: 'space-between', alignItems: 'center',
                padding: 'var(--space-3) var(--space-4)',
                borderBottom: i < arr.length - 1 ? '1px solid var(--border-primary)' : 'none',
              }}>
                <span style={{ fontSize: 'var(--text-sm)', color: 'var(--text-secondary)' }}>{r.label}</span>
                <span style={{ fontSize: 'var(--text-sm)', fontWeight: 600 }}>{r.value}</span>
              </div>
            ))}
          </div>

          {isCheque ? (
            <div style={{ padding: '10px 12px', borderRadius: 8, background: 'color-mix(in srgb, var(--color-info) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-info) 25%, transparent)', fontSize: 12, color: 'var(--text-secondary)' }}>
              سيُسجَّل هذا الشيك في أوراق القبض حتى تحصيله الفعلي
            </div>
          ) : hasCustodyLink ? (
            <div style={{ padding: '10px 12px', borderRadius: 8, background: 'color-mix(in srgb, var(--color-warning) 8%, transparent)', border: '1px solid color-mix(in srgb, var(--color-warning) 25%, transparent)', fontSize: 12, color: 'var(--text-secondary)', display: 'flex', gap: 6, alignItems: 'center' }}>
              <Wallet size={13} style={{ color: 'var(--color-warning)' }} /> سيُضاف لرصيد عهدة المندوب
            </div>
          ) : (
            <div className="form-group" style={{ margin: 0 }}>
              <label className="form-label required">الوجهة المالية</label>
              {filteredVaults.length === 0 ? (
                <div style={{ fontSize: 12, color: 'var(--color-danger)' }}>لا توجد خزائن نشطة</div>
              ) : (
                <select className="form-select" value={confirmVaultId}
                  onChange={e => setConfirmVaultId(e.target.value)}>
                  {filteredVaults.map(v => <option key={v.id} value={v.id}>{v.name}</option>)}
                </select>
              )}
            </div>
          )}
        </div>
      </Modal>

      {/* ── نافذة رفض الإيصال ── */}
      <Modal
        open={rejectOpen}
        onClose={() => setRejectOpen(false)}
        title="رفض الإيصال"
        size="sm"
        footer={
          <>
            <Button variant="ghost" onClick={() => setRejectOpen(false)} disabled={rejecting}>إلغاء</Button>
            <Button variant="danger" onClick={handleReject} loading={rejecting}
              icon={<XCircle size={14} />}>
              تأكيد الرفض
            </Button>
          </>
        }
      >
        <div className="flex-col gap-3">
          <div style={{ fontSize: 13, color: 'var(--text-secondary)' }}>
            إيصال <strong>{receipt.number}</strong> — {receipt.customer?.name} —{' '}
            <strong style={{ color: 'var(--color-danger)' }}>{formatCurrency(receipt.amount)}</strong>
          </div>
          <div className="form-group" style={{ margin: 0 }}>
            <label className="form-label required">سبب الرفض</label>
            <textarea className="form-textarea" rows={3} value={rejectReason}
              onChange={e => setRejectReason(e.target.value)}
              placeholder="اذكر سبب الرفض بوضوح..." style={{ resize: 'vertical' }} />
          </div>
        </div>
      </Modal>

    </div>
  )
}
