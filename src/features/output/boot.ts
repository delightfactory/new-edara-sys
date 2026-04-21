import { registerDocumentDefinition } from './definitions/document-registry';
import { paymentReceiptDefinition } from './definitions/payment-receipt.definition';
import { salesOrderDefinition } from './definitions/sales-order.definition';
import { accountStatementDefinition } from './definitions/account-statement.definition';
import { purchaseInvoiceDefinition } from './definitions/purchase-invoice.definition';
import { paymentVoucherDefinition } from './definitions/payment-voucher.definition';
import { creditPortfolioReportDefinition } from './definitions/credit-portfolio-report.definition';
import { repCreditCommitmentReportDefinition } from './definitions/rep-credit-commitment-report.definition';
import { repCreditCommitmentDetailReportDefinition } from './definitions/rep-credit-commitment-detail-report.definition';
import { reengagementReportDefinition } from './definitions/reengagement-report.definition';

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
  registerDocumentDefinition(creditPortfolioReportDefinition);
  registerDocumentDefinition(repCreditCommitmentReportDefinition);
  registerDocumentDefinition(repCreditCommitmentDetailReportDefinition);
  registerDocumentDefinition(reengagementReportDefinition);

  isBooted = true;
}

