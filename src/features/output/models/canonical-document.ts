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
