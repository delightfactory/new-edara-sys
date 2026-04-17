import { DocumentKind } from '../core/output-types';
import { DocumentDefinition } from './document-definition';

const registry = new Map<DocumentKind, DocumentDefinition>();

export function registerDocumentDefinition(def: DocumentDefinition) {
  if (registry.has(def.kind)) {
    // We intentionally overwrite instead of throwing an Error.
    // Engineering reason: Modern React frameworks like Vite heavily rely on HMR (Hot Module Replacement).
    // During development, module re-evaluation can trigger legitimate duplicate bootstraps.
    // Overwriting ensures fast-refresh works seamlessly while remaining safely idempotent in production.
    console.warn(`[Document Registry] Overwriting existing definition for kind: '${def.kind}' (Expected during HMR).`);
  }
  registry.set(def.kind, def);
}

export function getDocumentDefinition(kind: DocumentKind): DocumentDefinition | undefined {
  return registry.get(kind);
}

export function getAllDocumentKinds(): DocumentKind[] {
  return Array.from(registry.keys());
}

export function isDocumentKind(kind: string): kind is DocumentKind {
  return registry.has(kind as DocumentKind);
}
