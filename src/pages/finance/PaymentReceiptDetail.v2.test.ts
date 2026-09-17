import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { describe, expect, it } from 'vitest'

const sourcePath = fileURLToPath(new URL('./PaymentReceiptDetail.tsx', import.meta.url))
const source = readFileSync(sourcePath, 'utf8')

describe('PaymentReceiptDetail V2 transaction-header contract', () => {
  it('uses the shared Finance transaction header while preserving identity, context and output tooling', () => {
    expect(source).toContain("import { PaymentReceiptDetailHeader } from '@/components/finance/PaymentReceiptDetailPresentation'")
    expect(source).toContain('<PaymentReceiptDetailHeader')
    expect(source).toContain('receiptNumber={receipt.number}')
    expect(source).toContain('<CustomerLink id={receipt.customer.id} name={receipt.customer.name} />')
    expect(source).toContain("formatDateTime(receipt.created_at)")
    expect(source).toContain('status={receipt.status}')
    expect(source).toContain("onBack={() => navigate('/finance/payments')}")
    expect(source).toContain('tools={<DocumentActions kind="payment-receipt" entityId={receipt.id} />}')
    expect(source).not.toContain("<button onClick={() => navigate('/finance/payments')}")
  })

  it('keeps the existing Finance review eligibility predicates page-owned', () => {
    expect(source).toContain("receipt.status === 'pending'")
    expect(source).toContain("receipt.payment_method === 'cash'")
    expect(source).toContain('receipt.custody_id === myCustody.id')
    expect(source).toContain("const isAdmin = !!receipt && receipt.status === 'pending' && can('finance.payments.confirm')")
    expect(source).toContain('const canConfirm = isAdmin || isSelfCashCustody')
    expect(source).toContain('if (canConfirm) {')
    expect(source).toContain('if (isAdmin) {')
  })

  it('declares only the existing confirm/reject callbacks through canonical AppAction', () => {
    expect(source).toContain("import type { AppAction } from '@/components/patterns/ActionRegistry'")
    expect(source).toContain('const headerActions: AppAction[] = []')
    expect(source).toContain("id: 'confirm'")
    expect(source).toContain("label: isSelfCashCustody && !isAdmin ? 'تأكيد استلام النقدية' : 'تأكيد الاستلام'")
    expect(source).toContain('onSelect: openConfirm')
    expect(source).toContain("importance: 'primary'")
    expect(source).toContain("id: 'reject'")
    expect(source).toContain("onSelect: () => { setRejectReason(''); setRejectOpen(true) }")
    expect(source).toContain("tone: 'danger'")
    expect(source).toContain('actions={headerActions}')
  })

  it('preserves loading/not-found and all Finance mutation/service boundaries', () => {
    expect(source).toContain('if (isLoading) return (')
    expect(source).toContain("الإيصال غير موجود")
    expect(source).toContain('queryFn: () => getPaymentReceipt(id!)')
    expect(source).toContain('await confirmPaymentReceipt(receipt.id, (isCheque || hasCustodyLink) ? null : confirmVaultId)')
    expect(source).toContain('await rejectPaymentReceipt(receipt.id, rejectReason)')
    expect(source).toContain("invalidate('payment-receipts', 'payment-receipt', 'targets', 'target-detail', 'target-progress-history', 'target-reward-summary')")
    expect(source).toContain("invalidate('payment-receipts', 'payment-receipt')")
  })
})
