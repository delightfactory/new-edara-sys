import { DocumentKind } from '../core/output-types';

export interface CompanyBranding {
  name: string;
  nameEn?: string | null;
  logoUrl?: string | null;
  phone?: string | null;
  address?: string | null;
  taxNumber?: string | null;
  email?: string | null;
  website?: string | null;
  footerNote?: string | null;
  currencyCode: string;
  currencySymbol: string;
}

export interface CanonicalDocument {
  kind: DocumentKind;
  title: string;
  number?: string | null;
  status?: string | null;
  issuedAt?: string | null;
  direction: 'rtl' | 'ltr';
  locale: string;
  company: CompanyBranding;
  parties: Array<{
    role: string;
    name: string;
    code?: string | null;
    phone?: string | null;
    address?: string | null;
    taxNumber?: string | null;
  }>;
  meta: Array<{ label: string; value: string; dir?: 'rtl' | 'ltr' }>;
  sections: DocumentSection[];
  totals?: DocumentTotals | null;
  notes?: string[] | null;
  approvals?: Array<{ label: string; value: string }>;
}

/** A single product line in a thermal compact item list */
export interface CompactItem {
  /** Primary label — product name (may wrap to 2 lines) */
  name: string;
  /** e.g. "3 × 50.00" */
  qtyPrice: string;
  /** Optional detail line: unit, discount %, tax % */
  details?: string | null;
  /** Bold aligned total for this line */
  lineTotal: string;
}

export type DocumentSection =
  | { type: 'kv'; title?: string; rows: Array<{ label: string; value: string; dir?: 'rtl' | 'ltr' }> }
  | { type: 'table'; title?: string; columns: DocumentColumn[]; rows: DocumentRow[] }
  | { type: 'plain-text'; title?: string; content: string; dir?: 'rtl' | 'ltr' }
  | { type: 'summary'; title?: string; items: Array<{ label: string; value: string }> }
  | {
      /** Thermal-compact item list: each entry is one product line rendered as 2–3 stacked rows
       *  instead of a wide multi-column table. Backward-compatible — only ThermalLayout uses it. */
      type: 'compact-items';
      title?: string;
      items: CompactItem[];
    }
  | {
      /**
       * Customer card section — used exclusively by ReengagementReportLayout.
       * Other layouts never encounter this section type.
       */
      type: 'customer-card';
      title?: string;
      customers: CustomerCardEntry[];
    };

export interface DocumentColumn {
  key: string;
  label: string;
  align?: 'start' | 'center' | 'end';
  width?: string;
  dir?: 'rtl' | 'ltr';
  format?: 'currency' | 'number' | 'date' | 'text';
}

export type DocumentRow = Record<string, string | number | null>;

export interface DocumentTotals {
  subtotal?: string;
  discount?: string;
  tax?: string;
  total?: string;
  paid?: string;
  remaining?: string;
}

// ─── Customer Card Types (for ReengagementReportLayout) ──────────────────────

/** One product row inside a customer card */
export interface CustomerCardProduct {
  name: string;
  category: string | null;
  totalValue: string;
  orderCount: number;
  lastPurchase: string | null;
  status: string;
}

/** AR Aging bucket for customer card */
export interface CustomerCardAgingBucket {
  bucket: string;
  amount: number;
}

/** Payment behavior summary for customer card */
export interface CustomerCardPaymentBehavior {
  avgDelayDays: number | null;
  cashPct: number;
  chequePct: number;
  transferPct: number;
}

/** One 360° recommendation item */
export interface CustomerCardRecommendation {
  severity: 'critical' | 'warning' | 'opportunity' | 'positive' | 'info';
  title: string;
  reason?: string | null;
}

/** KPI summary for a single customer (360°) */
export interface CustomerCardKpis {
  netRevenue: number | null;
  totalCollected: number | null;
  orderCount: number | null;
  returnRatePct: number | null;
  creditUtilizationPct: number | null;
  customerSinceDays: number | null;
  outstandingBalance: number | null;
}

/** Full entry for one customer in a reengagement report card */
export interface CustomerCardEntry {
  // ── Basic fields (always present) ───────────────────────────
  customerId: string;
  customerName: string;
  customerCode: string | null;
  customerType: string;
  priorityLabel: string;       // e.g. 'CHAMPION_LOST'
  priorityDisplay: string;     // e.g. '🔴 Champion Lost'
  priorityAccent: string;      // hex color for the priority
  repName: string;
  governorate: string;
  city: string;
  historicalRevenue: number;
  revenueL90d: number;
  recencyDays: number | null;
  lastOrderDate: string | null;
  outstandingBalance: number;
  orderCount: number;
  valueTier: string;

  // ── 360° sections (null = not requested; Error = fetch failed) ──
  kpis360?: CustomerCardKpis | null | 'error';
  products360?: CustomerCardProduct[] | null | 'error';
  paymentBehavior360?: CustomerCardPaymentBehavior | null | 'error';
  recommendations360?: CustomerCardRecommendation[] | null | 'error';
  arAging360?: CustomerCardAgingBucket[] | null | 'error';
}
