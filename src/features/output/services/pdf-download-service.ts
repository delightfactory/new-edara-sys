/**
 * pdf-download-service.ts
 *
 * Thin re-export kept for backwards compatibility.
 * All actual popup logic has moved to: open-preview-popup.ts
 *
 * If you need to open a PDF popup, import openPreviewPopup directly:
 *   import { openPreviewPopup } from './open-preview-popup';
 *
 * This file is kept so any external call sites that imported
 * generateAndDownloadPdf do not break during migration.
 */
export { openPreviewPopup as generateAndDownloadPdf } from './open-preview-popup';
export type { PreviewPopupOptions as PdfDownloadOptions } from './open-preview-popup';
