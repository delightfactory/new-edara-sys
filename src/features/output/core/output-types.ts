export type OutputKind =
  | 'print'
  | 'pdf-browser'
  | 'pdf-download'
  | 'pdf-archive'
  | 'csv'
  | 'xlsx';

export type OutputTier = 'tier-1' | 'tier-2' | 'tier-3';

export type DocumentKind =
  | 'payment-receipt'
  | 'payment-voucher'
  | 'sales-order'
  | 'sales-invoice'
  | 'purchase-invoice'
  | 'account-statement'
  | 'credit-portfolio-report'
  | 'rep-credit-commitment-report'
  | 'rep-credit-commitment-detail-report'
  | 'reengagement-report'
  | 'report';

export type PaperProfileId =
  | 'a4-portrait'
  | 'a4-landscape'
  | 'letter-portrait'
  | 'legal-portrait'
  | 'thermal-58mm'
  | 'thermal-80mm'
  | 'custom';

export interface OutputRequest {
  documentKind: DocumentKind;
  outputKind: OutputKind;
  paperProfileId?: PaperProfileId;
  entityId?: string;
  filters?: Record<string, any>;
}

export interface OutputResult {
  success: boolean;
  artifactUrl?: string; // used for signed URLs in Tier-3 or blob URLs in Tier-1/Tier-2
  error?: string;
  message?: string;
}
