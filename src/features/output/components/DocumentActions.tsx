import React from 'react';
import { DocumentKind } from '../core/output-types';

interface DocumentActionsProps {
  kind: DocumentKind;
  entityId: string;
  className?: string;
  params?: Record<string, string>;
}

export function DocumentActions({ kind, entityId, className, params }: DocumentActionsProps) {
  const handlePreview = () => {
    // Open in a new tab to avoid breaking the current view and provide an isolated surface
    const query = new URLSearchParams(params || {}).toString();
    const url = `/documents/${kind}/${entityId}/preview${query ? '?' + query : ''}`;
    window.open(url, '_blank', 'noopener,noreferrer');
  };

  return (
    <div className={`document-actions ${className || ''}`} style={{ display: 'inline-block' }}>
      <button
        onClick={handlePreview}
        className="btn btn-secondary"
        style={{
          display: 'flex',
          alignItems: 'center',
          gap: '8px',
          padding: '8px 16px',
        }}
        title="معاينة / طباعة المستند"
      >
        <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <polyline points="6 9 6 2 18 2 18 9"></polyline>
          <path d="M6 18H4a2 2 0 0 1-2-2v-5a2 2 0 0 1 2-2h16a2 2 0 0 1 2 2v5a2 2 0 0 1-2 2h-2"></path>
          <rect x="6" y="14" width="12" height="8"></rect>
        </svg>
        <span>معاينة / طباعة</span>
      </button>
    </div>
  );
}
