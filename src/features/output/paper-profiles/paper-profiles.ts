import { PaperProfileId } from '../core/output-types';

export interface PaperProfile {
  id: PaperProfileId;
  name: string;
  size: { width: string; height: string } | 'auto'; // 'auto' mainly for thermal/continuous
  orientation: 'portrait' | 'landscape';
  margins: { top: string; right: string; bottom: string; left: string };
  fontScale: number;
  isThermal?: boolean;
  thermalConstraints?: {
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
  },
  'a4-landscape': {
    id: 'a4-landscape',
    name: 'A4 Landscape',
    size: { width: '297mm', height: '210mm' },
    orientation: 'landscape',
    margins: { top: '15mm', right: '15mm', bottom: '15mm', left: '15mm' },
    fontScale: 1.0,
  },
  'letter-portrait': {
    id: 'letter-portrait',
    name: 'Letter Portrait',
    size: { width: '8.5in', height: '11in' },
    orientation: 'portrait',
    margins: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    fontScale: 1.0,
  },
  'legal-portrait': {
    id: 'legal-portrait',
    name: 'Legal Portrait',
    size: { width: '8.5in', height: '14in' },
    orientation: 'portrait',
    margins: { top: '0.5in', right: '0.5in', bottom: '0.5in', left: '0.5in' },
    fontScale: 1.0,
  },
  'thermal-58mm': {
    id: 'thermal-58mm',
    name: 'Thermal 58mm',
    size: { width: '58mm', height: 'auto' },
    orientation: 'portrait',
    margins: { top: '5mm', right: '2mm', bottom: '5mm', left: '2mm' },
    fontScale: 0.85,
    isThermal: true,
    thermalConstraints: {
      hideImages: true,
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
    isThermal: true,
    thermalConstraints: {
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
  },
};
