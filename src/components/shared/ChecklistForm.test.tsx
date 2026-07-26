import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { render, screen, fireEvent, waitFor } from '@testing-library/react'
import ChecklistForm from './ChecklistForm'
import type { ChecklistQuestion } from '@/lib/types/activities'
import { compressImage } from '@/lib/utils/imageCompressor'

// Mock the image compressor
vi.mock('@/lib/utils/imageCompressor', () => ({
  compressImage: vi.fn(),
  validateOriginalFile: vi.fn(),
  validateImageDimensions: vi.fn()
}))

// Mock sonner toast
vi.mock('sonner', () => ({
  toast: {
    error: vi.fn(),
    success: vi.fn()
  }
}))

describe('ChecklistForm Component', () => {
  const mockQuestions: ChecklistQuestion[] = [
    {
      id: 'q-text',
      template_id: 't-1',
      question_text: 'السؤال النصي',
      question_type: 'text',
      is_required: true
    } as unknown as ChecklistQuestion,
    {
      id: 'q-photo',
      template_id: 't-1',
      question_text: 'سؤال الصورة',
      question_type: 'photo',
      is_required: true
    } as unknown as ChecklistQuestion
  ]

  let originalCreateObjectURL: PropertyDescriptor | undefined
  let originalRevokeObjectURL: PropertyDescriptor | undefined
  let originalCreateElement: PropertyDescriptor | undefined

  let createObjectURLMock: ReturnType<typeof vi.fn>
  let revokeObjectURLMock: ReturnType<typeof vi.fn>

  function restoreProperty(
    target: object,
    key: PropertyKey,
    descriptor: PropertyDescriptor | undefined
  ) {
    if (descriptor) {
      Object.defineProperty(target, key, descriptor)
    } else {
      Reflect.deleteProperty(target, key)
    }
  }

  beforeEach(() => {
    vi.clearAllMocks()

    originalCreateObjectURL = Object.getOwnPropertyDescriptor(globalThis.URL, 'createObjectURL')
    originalRevokeObjectURL = Object.getOwnPropertyDescriptor(globalThis.URL, 'revokeObjectURL')
    originalCreateElement = Object.getOwnPropertyDescriptor(document, 'createElement')

    createObjectURLMock = vi.fn().mockReturnValue('blob:http://localhost/mock-uuid')
    revokeObjectURLMock = vi.fn()

    Object.defineProperty(globalThis.URL, 'createObjectURL', {
      value: createObjectURLMock,
      configurable: true,
      writable: true
    })
    Object.defineProperty(globalThis.URL, 'revokeObjectURL', {
      value: revokeObjectURLMock,
      configurable: true,
      writable: true
    })
  })

  afterEach(() => {
    restoreProperty(globalThis.URL, 'createObjectURL', originalCreateObjectURL)
    restoreProperty(globalThis.URL, 'revokeObjectURL', originalRevokeObjectURL)
    restoreProperty(document, 'createElement', originalCreateElement)
    vi.restoreAllMocks()
  })

  it('renders correctly and enforces missing handler contract safely (no crash)', () => {
    const consoleErrorSpy = vi.spyOn(console, 'error').mockImplementation(() => {})

    render(
      <ChecklistForm
        questions={mockQuestions}
        activityId="act-1"
        templateId="t-1"
        photoMode="local-blob"
        onPhotoCapture={undefined} // missing handler
      />
    )

    // The component should render without throwing
    expect(screen.getByText('سؤال الصورة')).toBeDefined()

    // Capture button must be disabled and show safety message
    const photoBtn = screen.getByRole('button', { name: /التقاط الصور معطل حالياً بسبب خطأ في الإعداد/ })
    expect(photoBtn).toBeDefined()
    expect(photoBtn.hasAttribute('disabled')).toBe(true)

    // Console warning should be logged once
    expect(consoleErrorSpy).toHaveBeenCalledWith(
      expect.stringContaining('onPhotoCapture handler is required when photoMode is local-blob')
    )
    consoleErrorSpy.mockRestore()
  })

  it('supports photo capture and saves local_blob_id without Base64', async () => {
    const onPhotoCaptureMock = vi.fn().mockResolvedValue({ local_blob_id: 'new-local-blob-id' })
    const onChangeMock = vi.fn()

    render(
      <ChecklistForm
        questions={mockQuestions}
        activityId="act-1"
        templateId="t-1"
        photoMode="local-blob"
        onPhotoCapture={onPhotoCaptureMock}
        onChange={onChangeMock}
      />
    )

    const photoBtn = screen.getByRole('button', { name: 'التقاط صورة' })
    expect(photoBtn).toBeDefined()
    expect(photoBtn.hasAttribute('disabled')).toBe(false)

    // Setup compressImage resolve values
    const mockBlob = new Blob(['mockcontent'], { type: 'image/jpeg' })
    vi.mocked(compressImage).mockResolvedValueOnce({
      blob: mockBlob,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: 1000,
      checksum: 'hash123'
    })

    // Simulate input file selection
    const file = new File(['dummy content'], 'test.png', { type: 'image/png' })
    
    // Intercept input creation during click using a real element
    let createdInput: HTMLInputElement | null = null
    const rawCreateElement = document.createElement
    const createElementSpy = vi.spyOn(document, 'createElement').mockImplementation((tagName) => {
      const el = rawCreateElement.call(document, tagName)
      if (tagName === 'input') {
        createdInput = el as HTMLInputElement
      }
      return el
    })

    try {
      fireEvent.click(photoBtn)
      expect(createdInput).not.toBeNull()

      // Trigger changes on the real input element using fireEvent
      if (createdInput) {
        fireEvent.change(createdInput, {
          target: {
            files: [file]
          }
        })
      }

      await waitFor(() => {
        expect(compressImage).toHaveBeenCalledWith(file)
        expect(onPhotoCaptureMock).toHaveBeenCalledWith('q-photo', mockBlob, {
          mimeType: 'image/jpeg',
          extension: 'jpg',
          size: 1000,
          checksum: 'hash123'
        })
        expect(onChangeMock).toHaveBeenCalledWith(
          expect.arrayContaining([
            expect.objectContaining({
              question_id: 'q-photo',
              answer_json: { local_blob_id: 'new-local-blob-id' }
            })
          ]),
          false // isComplete is false because q-text (required) is empty
        )
      })
    } finally {
      createElementSpy.mockRestore()
    }
  })

  it('renders previews using object URLs and revokes them on replace and unmount', async () => {
    const loadLocalPhotoMock = vi.fn().mockResolvedValue(new Blob(['image-data']))
    const { rerender, unmount } = render(
      <ChecklistForm
        questions={mockQuestions}
        activityId="act-1"
        templateId="t-1"
        initialValues={{
          'q-photo': { local_blob_id: 'initial-blob-id' }
        }}
        photoMode="local-blob"
        onPhotoCapture={vi.fn()}
        loadLocalPhoto={loadLocalPhotoMock}
      />
    )

    // Verify preview component loads image via loadLocalPhoto
    await waitFor(() => {
      expect(loadLocalPhotoMock).toHaveBeenCalledWith('initial-blob-id')
      expect(createObjectURLMock).toHaveBeenCalled()
      const previewImg = screen.getByAltText('صورة ملتقطة')
      expect(previewImg).toBeDefined()
    })

    // Rerender with a different local_blob_id
    rerender(
      <ChecklistForm
        questions={mockQuestions}
        activityId="act-1"
        templateId="t-1"
        initialValues={{
          'q-photo': { local_blob_id: 'second-blob-id' }
        }}
        photoMode="local-blob"
        onPhotoCapture={vi.fn()}
        loadLocalPhoto={loadLocalPhotoMock}
      />
    )

    await waitFor(() => {
      // The previous object URL should be revoked!
      expect(revokeObjectURLMock).toHaveBeenCalled()
    })

    // Unmount
    unmount()
    expect(revokeObjectURLMock).toHaveBeenCalledTimes(2)
  })

  it('uses a native date input and emits an ISO date as answer_value', async () => {
    const onChangeMock = vi.fn()
    const dateQuestion = {
      id: 'q-date',
      template_id: 't-1',
      question_code: 'followup.next_date',
      question_text: 'تاريخ المتابعة التالي',
      question_type: 'date',
      is_required: true,
      options: [],
      default_value: null,
      hint_text: null,
      min_value: null,
      max_value: null,
      sort_order: 1,
      created_at: '2026-07-26T00:00:00Z',
    } satisfies ChecklistQuestion

    const { container } = render(
      <ChecklistForm
        questions={[dateQuestion]}
        activityId="act-1"
        templateId="t-1"
        onChange={onChangeMock}
      />
    )

    const input = container.querySelector<HTMLInputElement>('input[type="date"]')
    expect(input).not.toBeNull()
    fireEvent.change(input!, { target: { value: '2026-08-02' } })

    await waitFor(() => {
      expect(onChangeMock).toHaveBeenCalledWith([
        expect.objectContaining({
          question_id: 'q-date',
          answer_value: '2026-08-02',
          answer_json: null,
        }),
      ], true)
    })
  })
})
