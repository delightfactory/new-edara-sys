import React from 'react';
import { CanonicalDocument } from '../models/canonical-document';
import { PaperProfile } from '../paper-profiles/paper-profiles';
import { StandardLayout } from './layouts/StandardLayout';
import { ThermalLayout } from './layouts/ThermalLayout';
import { ReportLayout } from './layouts/ReportLayout';
import { ReengagementReportLayout } from './layouts/ReengagementReportLayout';

import '../styles/print-base.css';
import '../styles/print-a4.css';
import '../styles/print-thermal.css';
import '../styles/print-report.css';

interface DocumentRendererProps {
  document: CanonicalDocument;
  profile: PaperProfile;
}

export function DocumentRenderer({ document, profile }: DocumentRendererProps) {
  if (profile.isThermal || profile.id.startsWith('thermal')) {
    return <ThermalLayout document={document} profile={profile} />;
  }

  if (
    document.kind === 'report' ||
    document.kind === 'account-statement' ||
    document.kind === 'credit-portfolio-report' ||
    document.kind === 'rep-credit-commitment-report' ||
    document.kind === 'rep-credit-commitment-detail-report'
  ) {
    return <ReportLayout document={document} profile={profile} />;
  }

  if (document.kind === 'reengagement-report') {
    return <ReengagementReportLayout document={document} profile={profile} />;
  }

  return <StandardLayout document={document} profile={profile} />;
}
