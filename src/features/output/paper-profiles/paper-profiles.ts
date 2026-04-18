import { PaperProfileId } from '../core/output-types';

export interface PaperProfile {
  id: PaperProfileId;
  name: string;
  size: { width: string; height: string } | 'auto'; // 'auto' mainly for thermal/continuous
  orientation: 'portrait' | 'landscape';
  margins: { top: string; right: string; bottom: string; left: string };
  fontScale: number;
  pageNumbering: boolean;
  headerPolicy: 'fixed' | 'repeat' | 'first-page-only';
  footerPolicy: 'fixed' | 'repeat' | 'last-page-only';
  isThermal?: boolean;
  thermalConstraints?: {
    maxWidth: string;
    hideImages?: boolean;
    monochrome?: boolean;
  };
}

export const paperProfiles: Record<PaperProfileId, PaperProfile> = {
  'a4-portrait': {
    id: 'a4-portrait',
    name: 'A4 Portrait',
    size: { width: '210mm', height: '297mm' },
    orientation: 'portrait',
    margins: { top: '15mm', right: '15mm', bottom: '15mm', left: '15mm' },
    fontScale: 1.0,
    pageNumbering: true,
    headerPolicy: 'fixed',
    footerPolicy: 'fixed',
  },
  'a4-landscape': {
    id: 'a4-landscape',
    name: 'A4 Landscape',
    size: { width: '297mm', height: '210mm' },
    orientation: 'landscape',
    margins: { top: '15mm', right: '15mm', bottom: '15mm', left: '15mm' },
    fontScale: 1.0,
    pageNumbering: true,
    headerPolicy: 'fixed',
    footerPolicy: 'fixed',
  },
  'letter-portrait': {
    id: 'letter-portrait',
    name: 'Letter Portrait',
    size: { width: '8.5in', height: '11in' },
    orientation: 'portrait',
    margins: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    fontScale: 1.0,
    pageNumbering: true,
    headerPolicy: 'fixed',
    footerPolicy: 'fixed',
  },
  'legal-portrait': {
    id: 'legal-portrait',
    name: 'Legal Portrait',
    size: { width: '8.5in', height: '14in' },
    orientation: 'portrait',
    margins: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    fontScale: 1.0,
    pageNumbering: true,
    headerPolicy: 'fixed',
    footerPolicy: 'fixed',
  },
  'thermal-58mm': {
    id: 'thermal-58mm',
    name: 'Thermal 58mm',
    size: { width: '58mm', height: 'auto' },
    orientation: 'portrait',
    margins: { top: '5mm', right: '2mm', bottom: '5mm', left: '2mm' },
    fontScale: 0.85,
    pageNumbering: false,
    headerPolicy: 'first-page-only',
    footerPolicy: 'last-page-only',
    isThermal: true,
    thermalConstraints: {
      // maxWidth is applied as CSS var --thermal-max-width on .layout-thermal
      maxWidth: '54mm',
      // Production thermal printers: images cause paper jams or blank squares.
      // Set to false only for branded receipt printers that support rasterised logos.
      hideImages: true,
      // monochrome: strips all colour — thermal rollers are B&W only
      monochrome: true,
    },
  },
  'thermal-80mm': {
    id: 'thermal-80mm',
    name: 'Thermal 80mm',
    size: { width: '80mm', height: 'auto' },
    orientation: 'portrait',
    margins: { top: '5mm', right: '5mm', bottom: '5mm', left: '5mm' },
    fontScale: 0.95,
    pageNumbering: false,
    headerPolicy: 'first-page-only',
    footerPolicy: 'last-page-only',
    isThermal: true,
    thermalConstraints: {
      // maxWidth is applied as CSS var --thermal-max-width on .layout-thermal
      maxWidth: '72mm',
      // Production default: images suppressed for thermal-80mm path.
      hideImages: true,
      monochrome: true,
    },
  },
  'custom': {
    id: 'custom',
    name: 'Custom',
    size: 'auto',
    orientation: 'portrait',
    margins: { top: '10mm', right: '10mm', bottom: '10mm', left: '10mm' },
    fontScale: 1.0,
    pageNumbering: true,
    headerPolicy: 'fixed',
    footerPolicy: 'fixed',
  },
};
