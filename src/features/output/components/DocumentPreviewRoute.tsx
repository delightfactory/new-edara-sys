import React from 'react';
import { useParams } from 'react-router-dom';
import { DocumentPreviewPage } from './DocumentPreviewPage';

export default function DocumentPreviewRoute() {
  const { kind, id } = useParams<{ kind: string; id: string }>();

  if (!kind || !id) return <div style={{ direction: 'rtl', padding: '20px' }}>خطأ: الرابط غير مكتمل</div>;

  return <DocumentPreviewPage kind={kind} entityId={id} />;
}
