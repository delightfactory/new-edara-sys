import { StrictMode, useState, type ComponentType, type ReactNode } from 'react'
import { act, render, screen, within } from '@testing-library/react'
import userEvent from '@testing-library/user-event'
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest'
import { useModalStack } from '@/hooks/useModalStack'
import Modal from './Modal'
import ResponsiveModal from './ResponsiveModal'
import ConfirmDialog from './ConfirmDialog'

type DialogComponent = ComponentType<{ open: boolean; onClose: () => void; title?: string; children: ReactNode; disableOverlayClose?: boolean }>

function Fixture({ Dialog, autoFocus = false }: { Dialog: DialogComponent; autoFocus?: boolean }) {
  const [open, setOpen] = useState(false)
  const [version, setVersion] = useState(0)
  const [closedVersion, setClosedVersion] = useState<number | null>(null)
  return <>
    <button onClick={() => setOpen(true)}>فتح</button>
    <Dialog open={open} title="نافذة الاختبار" onClose={() => { setClosedVersion(version); setOpen(false) }}>
      <input aria-label="الحقل" autoFocus={autoFocus} />
      <button onClick={() => setVersion(value => value + 1)}>تغيير سياق</button>
      <button>الأخير</button>
    </Dialog>
    <button>خارج النافذة</button>
    <output aria-label="سياق الإغلاق">{closedVersion}</output>
  </>
}

describe('shared dialog lifecycle', () => {
  beforeEach(() => {
    document.body.style.overflow = 'clip'
    // jsdom has no layout. Only this geometry boundary is represented; the
    // actual focus/events, components, store and lifecycle remain unchanged.
    vi.spyOn(HTMLElement.prototype, 'getClientRects').mockImplementation(function (this: HTMLElement) {
      return (this.closest('[hidden]') || getComputedStyle(this).display === 'none'
        ? [] : [new DOMRect(0, 0, 20, 20)]) as unknown as DOMRectList
    })
  })
  afterEach(() => {
    vi.restoreAllMocks()
    document.body.style.overflow = ''
  })

  it.each([['legacy', Modal], ['responsive', ResponsiveModal]] as const)(
    '%s contains focus both ways, uses the latest callback and restores the opener and scroll',
    async (_, Dialog) => {
      const user = userEvent.setup()
      render(<StrictMode><Fixture Dialog={Dialog} /></StrictMode>)
      const opener = screen.getByRole('button', { name: 'فتح' })
      await user.click(opener)
      const dialog = screen.getByRole('dialog', { name: 'نافذة الاختبار' })
      expect(dialog).toBe(document.activeElement)
      expect(document.body.style.overflow).toBe('hidden')
      const controls = within(dialog)
      act(() => controls.getByRole('button', { name: 'الأخير' }).focus())
      await user.tab()
      expect(document.activeElement).toBe(controls.getByRole('button', { name: 'إغلاق' }))
      await user.tab({ shift: true })
      expect(document.activeElement).toBe(controls.getByRole('button', { name: 'الأخير' }))
      act(() => screen.getByRole('button', { name: 'خارج النافذة' }).focus())
      expect(document.activeElement).toBe(dialog)
      await user.click(controls.getByRole('button', { name: 'تغيير سياق' }))
      expect(document.activeElement).toBe(controls.getByRole('button', { name: 'تغيير سياق' }))
      await user.keyboard('{Escape}')
      expect(screen.queryByRole('dialog')).toBeNull()
      expect(document.activeElement).toBe(opener)
      expect(screen.getByLabelText('سياق الإغلاق').textContent).toBe('1')
      expect(document.body.style.overflow).toBe('clip')
      expect(useModalStack.getState().depth).toBe(0)
    },
  )

  it('retains a caller autofocus and still returns focus to the opener', async () => {
    const user = userEvent.setup()
    render(<StrictMode><Fixture Dialog={Modal} autoFocus /></StrictMode>)
    const opener = screen.getByRole('button', { name: 'فتح' })
    await user.click(opener)
    expect(document.activeElement).toBe(screen.getByLabelText('الحقل'))
    await user.keyboard('{Escape}')
    expect(document.activeElement).toBe(opener)
  })

  it('closes only the nested dialog, retaining parent focus, name, depth and scroll lock', async () => {
    function Nested() {
      const [parent, setParent] = useState(false)
      const [child, setChild] = useState(false)
      return <>
        <button onClick={() => setParent(true)}>فتح الأم</button>
        <ResponsiveModal open={parent} onClose={() => setParent(false)} title="الأم">
          <button onClick={() => setChild(true)}>فتح التابعة</button>
          <Modal open={child} onClose={() => setChild(false)} title="التابعة"><input aria-label="حقل التابعة" /></Modal>
        </ResponsiveModal>
        <ResponsiveModal open={false} onClose={() => {}} title="غير مفتوحة"><p>مغلقة</p></ResponsiveModal>
      </>
    }
    const user = userEvent.setup()
    const view = render(<StrictMode><Nested /></StrictMode>)
    await user.click(screen.getByRole('button', { name: 'فتح الأم' }))
    const childOpener = screen.getByRole('button', { name: 'فتح التابعة' })
    await user.click(childOpener)
    const ids = screen.getAllByRole('dialog').map(dialog => dialog.getAttribute('aria-labelledby'))
    expect(new Set(ids).size).toBe(2)
    expect(useModalStack.getState().depth).toBe(2)
    await user.keyboard('{Escape}')
    expect(screen.queryByRole('dialog', { name: 'التابعة' })).toBeNull()
    expect(screen.getByRole('dialog', { name: 'الأم' })).toBeTruthy()
    expect(document.activeElement).toBe(childOpener)
    expect(useModalStack.getState().depth).toBe(1)
    expect(document.body.style.overflow).toBe('hidden')
    view.unmount()
    expect(useModalStack.getState().depth).toBe(0)
    expect(document.body.style.overflow).toBe('clip')
  })

  it('keeps backdrop opt-out while allowing the existing Escape close', async () => {
    const onClose = vi.fn()
    const user = userEvent.setup()
    const view = render(<Modal open onClose={onClose} title="محمي" disableOverlayClose><p>المحتوى</p></Modal>)
    await user.click(view.container.querySelector('.modal-overlay')!)
    expect(onClose).not.toHaveBeenCalled()
    await user.keyboard('{Escape}')
    expect(onClose).toHaveBeenCalledTimes(1)
  })

  it('returns to the root opener when the parent removes an open child', async () => {
    function Group() {
      const [parent, setParent] = useState(false)
      const [child, setChild] = useState(false)
      return <>
        <button onClick={() => setParent(true)}>فتح المجموعة</button>
        <ResponsiveModal open={parent} onClose={() => setParent(false)} title="الأم">
          <button onClick={() => setChild(true)}>فتح التابعة</button>
          <ResponsiveModal open={child} onClose={() => setChild(false)} title="التابعة">
            <button onClick={() => setParent(false)}>إغلاق المجموعة</button>
          </ResponsiveModal>
        </ResponsiveModal>
      </>
    }
    const user = userEvent.setup()
    render(<StrictMode><Group /></StrictMode>)
    const opener = screen.getByRole('button', { name: 'فتح المجموعة' })
    await user.click(opener)
    await user.click(screen.getByRole('button', { name: 'فتح التابعة' }))
    await user.click(screen.getByRole('button', { name: 'إغلاق المجموعة' }))
    expect(screen.queryByRole('dialog')).toBeNull()
    expect(document.activeElement).toBe(opener)
    expect(useModalStack.getState().depth).toBe(0)
    expect(document.body.style.overflow).toBe('clip')
  })

  it('names confirmation, avoids implicit confirmation and contains focus with loading buttons disabled', async () => {
    const onConfirm = vi.fn(), onCancel = vi.fn()
    const user = userEvent.setup()
    const view = render(<ConfirmDialog open title="تأكيد العملية" onConfirm={onConfirm} onCancel={onCancel} />)
    const dialog = screen.getByRole('dialog', { name: 'تأكيد العملية' })
    await user.keyboard('{Enter}')
    expect(onConfirm).not.toHaveBeenCalled()
    await user.click(within(dialog).getByRole('button', { name: 'تأكيد' }))
    expect(onConfirm).toHaveBeenCalledTimes(1)
    view.rerender(<ConfirmDialog open loading title="تأكيد العملية" onConfirm={onConfirm} onCancel={onCancel} />)
    expect(within(dialog).getAllByRole('button').every(button => (button as HTMLButtonElement).disabled)).toBe(true)
    await user.tab()
    expect(document.activeElement).toBe(dialog)
    await user.keyboard('{Escape}')
    expect(onCancel).toHaveBeenCalledTimes(1)
    expect(onConfirm).toHaveBeenCalledTimes(1)
  })
})
