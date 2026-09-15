export const VISITS_ATOMIC_EXECUTION = import.meta.env.VITE_VISITS_ATOMIC_EXECUTION === 'true';

// Design System V2 rollout flags are opt-in so production behavior stays on the
// proven renderer until the replacement passes runtime visual acceptance.
export const DESIGN_SYSTEM_V2_SIDEBAR = import.meta.env.VITE_DESIGN_SYSTEM_V2_SIDEBAR === 'true';
