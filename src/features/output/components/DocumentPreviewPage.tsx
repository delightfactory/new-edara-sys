import React, { useCallback, useEffect, useRef, useState } from 'react';
import { getDocumentDefinition, isDocumentKind } from '../definitions/document-registry';
import { CanonicalDocument } from '../models/canonical-document';
import { PaperProfile, paperProfiles } from '../paper-profiles/paper-profiles';
import { browserPrintService } from '../services/browser-print-service';
import { DocumentRenderer } from '../renderers/DocumentRenderer';
import { DocumentDefinition } from '../definitions/document-definition';
import { resolveEnvironmentLocale } from '../utils/locale-resolver';
import { PaperProfileId } from '../core/output-types';

interface DocumentPreviewPageProps {
  kind: string;
  entityId: string;
}

/**
 * Committed state: profile and doc are always in sync.
 * committedProfile is only updated AFTER a successful build.
 * A failed rebuild leaves committedProfile/doc untouched.
 */
interface CommittedState {
  profile: PaperProfile;
  doc: CanonicalDocument;
}

export function DocumentPreviewPage({ kind, entityId }: DocumentPreviewPageProps) {
  const [committed, setCommitted] = useState<CommittedState | null>(null);
  const [definition, setDefinition] = useState<DocumentDefinition | null>(null);
  const [loading, setLoading] = useState(true);
  const [rebuilding, setRebuilding] = useState(false);
  const [rebuildError, setRebuildError] = useState<string | null>(null);
  const [fatalError, setFatalError] = useState<string | null>(null);

  // ── Race-condition guard ──────────────────────────────────────────
  // Each build invocation gets a token; only the latest token may commit its result.
  const buildTokenRef = useRef<number>(0);

  // ── Core build function ──────────────────────────────────────────
  const buildDoc = useCallback(async (
    def: DocumentDefinition,
    paperProfileId: PaperProfileId,
    filters: Record<string, any>,
    token: number
  ): Promise<{ doc: CanonicalDocument; profile: PaperProfile } | null> => {
    const { locale: fallbackLocale, direction: fallbackDir } = resolveEnvironmentLocale();
    const builtDoc = await def.fetchAndBuild({
      entityId,
      locale: fallbackLocale,
      direction: fallbackDir,
      filters,
      paperProfileId,
    });

    // If a newer build was started while we were awaiting, discard this result.
    if (token !== buildTokenRef.current) return null;

    return { doc: builtDoc, profile: paperProfiles[paperProfileId] };
  }, [entityId]);

  // ── Parse URL filters (memoised, stable across re-renders) ───────
  const getFilters = useCallback((): Record<string, any> => {
    const searchParams = new URLSearchParams(window.location.search);
    const filters: Record<string, any> = {};
    searchParams.forEach((val, key) => { filters[key] = val; });
    return filters;
  }, []);

  // ── Initial load ─────────────────────────────────────────────────
  useEffect(() => {
    async function initialFetch() {
      try {
        setLoading(true);
        setFatalError(null);
        if (!isDocumentKind(kind)) throw new Error(`Invalid document kind: ${kind}`);

        const def = getDocumentDefinition(kind);
        if (!def) throw new Error(`Document definition not registered: ${kind}`);

        setDefinition(def);

        const token = ++buildTokenRef.current;
        const result = await buildDoc(def, def.defaultPaper, getFilters(), token);
        if (!result) return; // superseded — safe to ignore

        setCommitted(result); // profile + doc committed atomically
      } catch (err: any) {
        setFatalError(err.message);
      } finally {
        setLoading(false);
      }
    }
    initialFetch();
  }, [kind, entityId, buildDoc, getFilters]);

  // ── Rebuild on paper selection change ────────────────────────────
  const handleProfileChange = useCallback(async (newProfileId: PaperProfileId) => {
    if (!definition) return;
    if (!paperProfiles[newProfileId]) return;

    // Issue a new token — any in-flight build with an older token will self-discard.
    const token = ++buildTokenRef.current;

    setRebuilding(true);
    setRebuildError(null);

    try {
      const result = await buildDoc(definition, newProfileId, getFilters(), token);
      if (!result) return; // superseded — self-discard, leave committed state intact

      // Only commit atomically when build succeeds AND token is still current.
      setCommitted(result);
    } catch (err: any) {
      // Build failed: leave committed state (profile + doc) completely intact.
      setRebuildError(`فشل تغيير المقاس: ${err.message}`);
    } finally {
      // Only clear rebuilding indicator if we still own the latest token.
      if (token === buildTokenRef.current) setRebuilding(false);
    }
  }, [definition, buildDoc, getFilters]);

  // ── Preview route class ──────────────────────────────────────────
  useEffect(() => {
    document.body.classList.add('is-preview-route');
    return () => { document.body.classList.remove('is-preview-route'); };
  }, []);

  // ── Fatal states ─────────────────────────────────────────────────
  if (loading) return (
    <div style={{ padding: '2rem', textAlign: 'center', direction: 'rtl' }}>
      جاري تحضير المستند...
    </div>
  );
  if (fatalError) return (
    <div style={{ color: '#c00', padding: '2rem', direction: 'rtl', fontWeight: 600 }}>{fatalError}</div>
  );
  if (!committed) return null;

  const { profile, doc } = committed;
  const containerDir = doc.direction;

  // The select shows the committed profile id (what the current rendered doc actually is).
  // While rebuilding it is disabled, preventing a new change from compounding.
  const displayProfileId = profile.id;

  return (
    <div style={{ background: '#d8d8d8', minHeight: '100vh', padding: '20px 0', direction: containerDir }}>

      {/* ── Action Bar ────────────────────────────────────────────── */}
      <div
        className="preview-action-bar"
        style={{
          position: 'fixed', top: 0, left: 0, right: 0,
          background: 'white', padding: '8px 20px',
          boxShadow: '0 2px 6px rgba(0,0,0,0.12)',
          display: 'flex', gap: '10px', justifyContent: 'center',
          alignItems: 'center', zIndex: 1000,
        }}
        dir="rtl"
      >
        {/* Paper selector — shows committed profile; disabled while rebuilding */}
        <select
          value={displayProfileId}
          disabled={rebuilding}
          onChange={(e) => handleProfileChange(e.target.value as PaperProfileId)}
          style={{
            padding: '5px 10px',
            border: '1px solid #bbb',
            borderRadius: '4px',
            fontFamily: 'inherit',
            fontSize: '13px',
            opacity: rebuilding ? 0.6 : 1,
          }}
        >
          {definition?.supportedPapers.map(pid => (
            <option key={pid} value={pid}>{paperProfiles[pid].name}</option>
          ))}
        </select>

        {/* Rebuilding indicator */}
        {rebuilding && (
          <span style={{ fontSize: '12px', color: '#555', direction: 'rtl' }}>
            جاري إعادة البناء...
          </span>
        )}

        {/* Non-fatal rebuild error (committed state preserved) */}
        {rebuildError && !rebuilding && (
          <span
            style={{ fontSize: '12px', color: '#c00', direction: 'rtl', cursor: 'pointer' }}
            onClick={() => setRebuildError(null)}
            title="انقر لإغلاق"
          >
            ⚠ {rebuildError}
          </span>
        )}

        {/* Print button */}
        <button
          onClick={() => browserPrintService.print()}
          disabled={rebuilding}
          style={{
            padding: '6px 22px',
            background: rebuilding ? '#888' : '#0055cc',
            color: 'white', border: 'none',
            borderRadius: '4px', cursor: rebuilding ? 'not-allowed' : 'pointer',
            fontWeight: 'bold', fontSize: '13px',
            fontFamily: 'inherit',
          }}
        >
          طباعة / حفظ PDF
        </button>
      </div>

      {/* ── Dynamic @page + CSS variables ───────────────────────── */}
      <style>
        {`
          @media print {
            .preview-action-bar { display: none !important; }
            body, html { background: white !important; }
            .output-print-root { margin-top: 0 !important; }
            @page {
              size: ${profile.size === 'auto' ? 'auto' : `${profile.size.width} ${profile.size.height}`};
              margin: ${profile.margins.top} ${profile.margins.right} ${profile.margins.bottom} ${profile.margins.left};
            }
          }
          .output-print-root {
            --profile-width: ${profile.size === 'auto' ? '100%' : profile.size.width};
            --profile-height: ${profile.size === 'auto' ? 'auto' : profile.size.height};
            --profile-pad-t: ${profile.margins.top};
            --profile-pad-r: ${profile.margins.right};
            --profile-pad-b: ${profile.margins.bottom};
            --profile-pad-l: ${profile.margins.left};
          }
        `}
      </style>

      {/* ── Printable Surface ─────────────────────────────────────── */}
      <div
        className="output-print-root"
        style={{
          marginTop: '54px',
          opacity: rebuilding ? 0.4 : 1,
          transition: 'opacity 0.15s',
        }}
      >
        <DocumentRenderer document={doc} profile={profile} />
      </div>
    </div>
  );
}
