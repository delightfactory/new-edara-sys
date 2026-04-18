/**
 * platform-capabilities.ts
 *
 * Central resolver for output capability gating.
 * Determines what output actions are ACTUALLY supported on a given
 * platform × paper-profile × document combination.
 *
 * ── Decision table ───────────────────────────────────────────────────
 *
 *  Platform  │ Paper   │ print │ pdf-browser │ pdf-download
 * ───────────┼─────────┼───────┼─────────────┼─────────────
 *  desktop   │ A4/Ltr  │  ✅   │     ✅      │     ✅
 *  desktop   │ thermal │  ✅   │     ✅      │     ✅ *
 *  android   │ A4/Ltr  │  ✅   │     ✅      │     ❌ (popup blocked)
 *  android   │ thermal │  ✅   │     ✅      │     ❌
 *  ios       │ A4/Ltr  │  ✅   │     ❌      │     ❌
 *  ios       │ thermal │  ✅   │     ❌      │     ❌
 *
 * * Desktop + thermal pdf-download: allowed, but the @page rule is
 *   unreliable on non-Chrome browsers. No false promise is made.
 *
 * ── Why ios pdf-browser is ❌ ────────────────────────────────────────
 * "pdf-browser" uses window.open() → the user must manually Save/Print
 * from the popup. On iOS Safari, the print dialog IS accessible but
 * window.open called after `await import()` is **blocked by the browser
 * as an unsolicited popup**. The only safe path on iOS is triggering
 * window.print() directly in the same window (the `print` output kind).
 *
 * ── Why android pdf-download is ❌ ──────────────────────────────────
 * android Chrome allows window.open() from a user gesture, but
 * the popup-then-autoprint flow is unreliable (print dialog behaviour
 * differs across OEM Chrome builds). Gated to avoid inconsistency.
 */

import { OutputKind, PaperProfileId } from './output-types';

export type Platform = 'desktop' | 'android' | 'ios';

// ── Platform detection ────────────────────────────────────────────────
// Called ONCE per session. Not reactive — no resize listener needed.
export function detectPlatform(): Platform {
  if (typeof navigator === 'undefined') return 'desktop';

  const ua = navigator.userAgent;

  // iPadOS 13+ reports itself as Macintosh — check for touch + no pointer
  const isIpad =
    /iPad/.test(ua) ||
    (navigator.platform === 'MacIntel' &&
      typeof navigator.maxTouchPoints === 'number' &&
      navigator.maxTouchPoints > 1);

  if (/iPhone/.test(ua) || isIpad) return 'ios';

  if (/Android/.test(ua)) return 'android';

  return 'desktop';
}

// Singleton — evaluated once at import time.
export const CURRENT_PLATFORM: Platform = detectPlatform();

// ── Thermal paper helper ─────────────────────────────────────────────
export function isThermalProfile(paperId: PaperProfileId | string): boolean {
  return paperId.startsWith('thermal');
}

// ── Main resolver ────────────────────────────────────────────────────
export interface CapabilityResolution {
  allowed: boolean;
  /** If false, the UI must NOT show this option at all */
  visible: boolean;
  /** Human-readable reason for gating — shown only in dev/debug */
  reason?: string;
}

export function resolveOutputCapability(
  outputKind: OutputKind,
  platform: Platform,
  paperProfileId: PaperProfileId | string,
): CapabilityResolution {
  const thermal = isThermalProfile(paperProfileId);

  // ── print: always allowed ─────────────────────────────────────────
  if (outputKind === 'print') {
    return { allowed: true, visible: true };
  }

  // ── pdf-browser ───────────────────────────────────────────────────
  if (outputKind === 'pdf-browser') {
    if (platform === 'ios') {
      return {
        allowed: false,
        visible: false,
        reason: 'iOS Safari blocks popup windows opened after async operations',
      };
    }
    // All other platforms: show but note limitation for thermal
    return { allowed: true, visible: true };
  }

  // ── pdf-download ─────────────────────────────────────────────────
  if (outputKind === 'pdf-download') {
    if (platform === 'ios') {
      return {
        allowed: false,
        visible: false,
        reason: 'iOS Safari: window.open() blocked after async import — no reliable PDF path',
      };
    }
    if (platform === 'android') {
      return {
        allowed: false,
        visible: false,
        reason: 'Android Chrome: popup-then-autoprint is unreliable across OEM builds',
      };
    }
    if (thermal && platform === 'desktop') {
      // Allowed on desktop only — @page size works in Chrome/Edge
      // but output may not be truly thermal-sized in all browsers.
      return {
        allowed: true,
        visible: true,
        reason: 'Desktop only: @page thermal size applies in Chrome/Edge; other browsers render A4',
      };
    }
    if (thermal) {
      return {
        allowed: false,
        visible: false,
        reason: 'Thermal PDF-download only supported on desktop Chrome/Edge',
      };
    }
    // desktop + A4
    return { allowed: true, visible: true };
  }

  // All other output kinds (csv, xlsx, pdf-archive) — not implemented
  return {
    allowed: false,
    visible: false,
    reason: `OutputKind "${outputKind}" is not implemented end-to-end`,
  };
}

// ── Bulk resolver for useDocumentOutput ──────────────────────────────
export function resolveAllCapabilities(
  supportedOutputs: OutputKind[],
  platform: Platform,
  paperProfileId: PaperProfileId | string,
): Array<{ kind: OutputKind; allowed: boolean; visible: boolean; label: string }> {
  return supportedOutputs
    .map(kind => {
      const res = resolveOutputCapability(kind, platform, paperProfileId);
      return { kind, ...res, label: outputLabel(kind) };
    })
    .filter(c => c.visible);
}

function outputLabel(kind: OutputKind): string {
  switch (kind) {
    case 'print':        return 'طباعة';
    case 'pdf-browser':  return 'معاينة PDF';
    case 'pdf-download': return 'حفظ كـ PDF';
    default:             return kind;
  }
}
