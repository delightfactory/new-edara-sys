import { useCallback, useLayoutEffect, useRef, type FocusEvent, type RefObject } from 'react'
import { useModalStack } from './useModalStack'

interface DialogEntry { element: HTMLDivElement }
const dialogs: DialogEntry[] = []
let previousOverflow = ''

function focusableElements(dialog: HTMLDivElement) {
  return Array.from(dialog.querySelectorAll<HTMLElement>(
    'button, a[href], input, select, textarea, [tabindex], [contenteditable="true"]',
  )).filter(element => element.tabIndex >= 0
    && !element.matches(':disabled')
    && !element.closest('[inert]')
    && element.getClientRects().length > 0
    && getComputedStyle(element).visibility === 'visible')
}

/** Shared lifecycle for the two existing div-based dialog presentations. */
export function useDialogLifecycle(
  open: boolean,
  contentRef: RefObject<HTMLDivElement>,
  onClose: () => void,
) {
  const closeRef = useRef(onClose)
  const openerRef = useRef<HTMLElement | null>(null)
  useLayoutEffect(() => { closeRef.current = onClose }, [onClose])

  // React autoFocus can run before the layout effect; retain its related target.
  const onFocusCapture = useCallback((event: FocusEvent<HTMLDivElement>) => {
    if (open && !openerRef.current && event.relatedTarget instanceof HTMLElement
      && !event.currentTarget.contains(event.relatedTarget)) {
      openerRef.current = event.relatedTarget
    }
  }, [open])

  useLayoutEffect(() => {
    const dialog = contentRef.current
    if (!open || !dialog) return
    if (!dialog.contains(document.activeElement)) {
      openerRef.current = document.activeElement instanceof HTMLElement ? document.activeElement : null
    }
    const entry = { element: dialog }
    if (dialogs.length === 0) previousOverflow = document.body.style.overflow
    // Child layout effects run first when parent and child mount together.
    const descendant = dialogs.findIndex(item => dialog.contains(item.element))
    if (descendant < 0) dialogs.push(entry)
    else dialogs.splice(descendant, 0, entry)
    document.body.style.overflow = 'hidden'
    useModalStack.getState().push()
    const isTop = () => dialogs.at(-1) === entry

    const containFocus = (event: globalThis.FocusEvent) => {
      if (isTop() && event.target instanceof Node && !dialog.contains(event.target)) dialog.focus()
    }
    const keydown = (event: KeyboardEvent) => {
      if (!isTop() || event.defaultPrevented) return
      if (event.key === 'Escape') {
        event.preventDefault()
        event.stopPropagation()
        closeRef.current()
        return
      }
      if (event.key !== 'Tab') return
      const controls = focusableElements(dialog)
      const active = document.activeElement
      if (controls.length === 0) {
        event.preventDefault()
        dialog.focus()
      } else if (event.shiftKey && (active === controls[0] || active === dialog)) {
        event.preventDefault()
        controls.at(-1)?.focus()
      } else if (!event.shiftKey && (active === controls.at(-1) || active === dialog)) {
        event.preventDefault()
        controls[0].focus()
      }
    }
    document.addEventListener('focusin', containFocus)
    document.addEventListener('keydown', keydown)
    if (isTop() && !dialog.contains(document.activeElement)) dialog.focus()

    return () => {
      const wasTop = isTop()
      document.removeEventListener('focusin', containFocus)
      document.removeEventListener('keydown', keydown)
      const index = dialogs.indexOf(entry)
      if (index >= 0) dialogs.splice(index, 1)
      useModalStack.getState().pop()
      if (dialogs.length === 0) document.body.style.overflow = previousOverflow
      const opener = openerRef.current
      openerRef.current = null
      if (wasTop) {
        const remaining = dialogs.at(-1)?.element
        if (opener?.isConnected && (!remaining || remaining.contains(opener))) opener.focus()
        else remaining?.focus()
      }
    }
  }, [open, contentRef])

  return onFocusCapture
}
