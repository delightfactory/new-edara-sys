import { registerDocumentDefinition } from './document-registry';
import { paymentReceiptDefinition } from './payment-receipt.definition';

// boot.ts handles the actual bootstrapping at app startup.

export * from './document-registry';
export { paymentReceiptDefinition };
