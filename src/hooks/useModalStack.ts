/**
 * useModalStack — Smart FAB visibility controller
 *
 * Any component that opens a modal/sheet calls push() and pop() (or use the
 * convenience hook `useModalPresence`).  The FAB reads `isAnyModalOpen` and
 * hides itself while any modal is on the stack.
 *
 * Design decision: a simple reference-counted integer is enough.  We *don't*
 * store modal IDs because we only need a boolean (visible/hidden) for the FAB.
 */
import { create } from 'zustand'

interface ModalStackState {
  depth: number
  push: () => void
  pop:  () => void
}

export const useModalStack = create<ModalStackState>((set) => ({
  depth: 0,
  push: () => set((s) => ({ depth: s.depth + 1 })),
  pop:  () => set((s) => ({ depth: Math.max(0, s.depth - 1) })),
}))

/** True while at least one modal/sheet is open */
export const useIsAnyModalOpen = () => useModalStack((s) => s.depth > 0)
