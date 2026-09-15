import { act, render, screen } from '@testing-library/react'
import { describe, expect, it } from 'vitest'
import ResponsiveCollection from './ResponsiveCollection'

function setViewport(width: number) {
  Object.defineProperty(window, 'innerWidth', {
    configurable: true,
    writable: true,
    value: width,
  })
  act(() => window.dispatchEvent(new Event('resize')))
}

const renderers = {
  renderDesktop: (items: number[]) => <div>desktop:{items.join(',')}</div>,
  renderTablet: (items: number[]) => <div>tablet:{items.join(',')}</div>,
  renderMobile: (items: number[]) => <div>mobile:{items.join(',')}</div>,
}

describe('ResponsiveCollection', () => {
  it('mounts only the mobile renderer on a mobile viewport', () => {
    setViewport(390)
    render(<ResponsiveCollection items={[1, 2]} {...renderers} />)

    expect(screen.getByText('mobile:1,2')).toBeTruthy()
    expect(screen.queryByText('tablet:1,2')).toBeNull()
    expect(screen.queryByText('desktop:1,2')).toBeNull()
  })

  it('uses the explicit tablet renderer on tablet widths', () => {
    setViewport(900)
    render(<ResponsiveCollection items={[3]} {...renderers} />)

    expect(screen.getByText('tablet:3')).toBeTruthy()
    expect(screen.queryByText('mobile:3')).toBeNull()
    expect(screen.queryByText('desktop:3')).toBeNull()
  })

  it('can deliberately fall back to the mobile composition on tablet', () => {
    setViewport(900)
    render(
      <ResponsiveCollection
        items={[4]}
        renderDesktop={renderers.renderDesktop}
        renderMobile={renderers.renderMobile}
        tabletFallback="mobile"
      />
    )

    expect(screen.getByText('mobile:4')).toBeTruthy()
    expect(screen.queryByText('desktop:4')).toBeNull()
  })

  it('renders shared loading and empty states before device composition', () => {
    setViewport(1440)
    const { rerender } = render(
      <ResponsiveCollection
        items={[] as number[]}
        loading
        loadingState={<div>loading-state</div>}
        {...renderers}
      />
    )

    expect(screen.getByText('loading-state')).toBeTruthy()

    rerender(
      <ResponsiveCollection
        items={[] as number[]}
        emptyState={<div>empty-state</div>}
        {...renderers}
      />
    )

    expect(screen.getByText('empty-state')).toBeTruthy()
  })
})
