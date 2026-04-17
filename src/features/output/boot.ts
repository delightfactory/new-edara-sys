import { registerDocumentDefinition } from './definitions/document-registry';
import { paymentReceiptDefinition } from './definitions/payment-receipt.definition';
import { salesOrderDefinition } from './definitions/sales-order.definition';
import { accountStatementDefinition } from './definitions/account-statement.definition';
import { purchaseInvoiceDefinition } from './definitions/purchase-invoice.definition';
import { paymentVoucherDefinition } from './definitions/payment-voucher.definition';

let isBooted = false;

/**
 * Initializes the Output Platform completely.
 * Safely idempotent. Must be called at app startup to register all document definitions.
 */
export function bootOutputPlatform(): void {
  if (isBooted) return;

  registerDocumentDefinition(paymentReceiptDefinition);
  registerDocumentDefinition(salesOrderDefinition);
  registerDocumentDefinition(accountStatementDefinition);
  registerDocumentDefinition(purchaseInvoiceDefinition);
  registerDocumentDefinition(paymentVoucherDefinition);

  isBooted = true;
}
