export const VISITS_ATOMIC_EXECUTION = import.meta.env.VITE_VISITS_ATOMIC_EXECUTION === 'true';

// AI Operations is intentionally disabled by default until its database migrations
// are explicitly reviewed and applied. Preview mode uses local fixtures only and
// must never issue AI Operations RPCs.
export const AI_OPERATIONS_PREVIEW = import.meta.env.VITE_AI_OPERATIONS_PREVIEW === 'true';
export const AI_OPERATIONS_DATA_MODE: 'preview' | 'rpc' =
  import.meta.env.VITE_AI_OPERATIONS_DATA_MODE === 'rpc' ? 'rpc' : 'preview';
