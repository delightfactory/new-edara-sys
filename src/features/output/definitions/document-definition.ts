import { DocumentKind, OutputKind, PaperProfileId } from '../core/output-types';
import { CanonicalDocument } from '../models/canonical-document';

export interface DocumentDefinition<TEntity = any, TFilters = any> {
  kind: DocumentKind;
  title: string;
  defaultPaper: PaperProfileId;
  supportedOutputs: OutputKind[];
  supportedPapers: PaperProfileId[];
  isArchivable: boolean;
  maxSyncPages: number;

  fetchAndBuild: (
    params: {
      entityId?: string;
      filters?: TFilters;
      locale: string;
      direction: 'rtl' | 'ltr';
      /** The target paper profile — allows definitions to return a different
       *  CanonicalDocument structure (e.g. thermal compact vs A4 full). */
      paperProfileId?: PaperProfileId;
    }
  ) => Promise<CanonicalDocument>;

  exportSchema?: {
    columns: Array<{ key: string; header: string; width?: number }>;
    buildRows: (entities: TEntity[]) => Array<Record<string, any>>;
  };
}
