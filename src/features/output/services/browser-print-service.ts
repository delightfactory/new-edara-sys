/**
 * browser-print-service.ts
 *
 * Professional print readiness pipeline replacing blind setTimeout.
 *
 * Readiness chain (in order):
 *   1. document.fonts.ready  — waits for all declared web fonts
 *   2. requestAnimationFrame — ensures a paint has been scheduled
 *   3. requestAnimationFrame — second rAF for paint flush (double-rAF)
 *
 * Only after this chain resolves is window.print() called.
 *
 * Watchdog: a 30 s watchdog terminates the isPrinting lock if afterprint
 * never fires (e.g. iOS Safari). It does NOT call window.print() again —
 * it only releases the lock so the service can be reused.
 *
 * iOS note:
 *   afterprint is dispatched on iOS Safari ≥ 16.4 but was absent in
 *   earlier versions. The watchdog handles the case gracefully.
 */

const WATCHDOG_MS = 30_000;

class BrowserPrintService {
  private isPrinting = false;

  /**
   * Waits for font + paint readiness, then calls window.print().
   * Returns a promise that resolves when afterprint fires (or watchdog
   * triggers). Returns false if already printing.
   */
  public async print(): Promise<boolean> {
    if (this.isPrinting) return false;
    this.isPrinting = true;

    try {
      await this.waitForReadiness();
    } catch {
      // Readiness failure should not block print — proceed anyway
    }

    return new Promise<boolean>((resolve) => {
      let watchdogTimer: ReturnType<typeof setTimeout> | null = null;

      const cleanup = () => {
        if (watchdogTimer !== null) clearTimeout(watchdogTimer);
        window.removeEventListener('afterprint', onAfterPrint);
        window.removeEventListener('beforeprint', onBeforePrint);
        this.isPrinting = false;
        document.body.classList.remove('is-printing');
        resolve(true);
      };

      const onAfterPrint = () => cleanup();

      const onBeforePrint = () => {
        document.body.classList.add('is-printing');
      };

      window.addEventListener('afterprint', onAfterPrint, { once: true });
      window.addEventListener('beforeprint', onBeforePrint, { once: true });

      // Watchdog: releases lock if afterprint never fires (iOS < 16.4, etc.)
      watchdogTimer = setTimeout(() => {
        if (this.isPrinting) cleanup();
      }, WATCHDOG_MS);

      window.print();
    });
  }

  /**
   * Waits for:
   *   1. document.fonts.ready (web font loading)
   *   2. Two animation frames   (layout + paint stabilization)
   */
  private waitForReadiness(): Promise<void> {
    return new Promise<void>((resolve) => {
      const afterFonts = () => {
        // Double rAF: first schedules a layout pass, second waits for paint
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            resolve();
          });
        });
      };

      if (typeof document.fonts?.ready?.then === 'function') {
        document.fonts.ready.then(afterFonts).catch(afterFonts);
      } else {
        afterFonts();
      }
    });
  }
}

export const browserPrintService = new BrowserPrintService();
