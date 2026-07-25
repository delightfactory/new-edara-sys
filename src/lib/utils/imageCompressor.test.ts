import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest'
import { compressImage, validateImageDimensions } from './imageCompressor'

describe('imageCompressor Utility', () => {
  let originalCreateObjectURL: PropertyDescriptor | undefined
  let originalRevokeObjectURL: PropertyDescriptor | undefined
  let originalCrypto: PropertyDescriptor | undefined
  let originalImage: PropertyDescriptor | undefined
  let originalCreateElement: PropertyDescriptor | undefined

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
    // Preserve exact descriptors
    originalCreateObjectURL = Object.getOwnPropertyDescriptor(globalThis.URL, 'createObjectURL')
    originalRevokeObjectURL = Object.getOwnPropertyDescriptor(globalThis.URL, 'revokeObjectURL')
    originalCrypto = Object.getOwnPropertyDescriptor(globalThis, 'crypto')
    originalImage = Object.getOwnPropertyDescriptor(globalThis, 'Image')
    originalCreateElement = Object.getOwnPropertyDescriptor(document, 'createElement')

    // Mock createObjectURL & revokeObjectURL
    Object.defineProperty(globalThis.URL, 'createObjectURL', {
      value: vi.fn().mockReturnValue('blob:http://localhost/mock-uuid'),
      configurable: true,
      writable: true
    })
    Object.defineProperty(globalThis.URL, 'revokeObjectURL', {
      value: vi.fn(),
      configurable: true,
      writable: true
    })

    // Mock Crypto subtle digest
    const mockDigest = vi.fn().mockResolvedValue(new Uint8Array([1, 2, 3]).buffer)
    Object.defineProperty(globalThis, 'crypto', {
      value: {
        subtle: {
          digest: mockDigest
        }
      },
      configurable: true,
      writable: true
    })
  })

  afterEach(() => {
    // Restore descriptors cleanly
    restoreProperty(globalThis.URL, 'createObjectURL', originalCreateObjectURL)
    restoreProperty(globalThis.URL, 'revokeObjectURL', originalRevokeObjectURL)
    restoreProperty(globalThis, 'crypto', originalCrypto)
    restoreProperty(globalThis, 'Image', originalImage)
    restoreProperty(document, 'createElement', originalCreateElement)
    vi.restoreAllMocks()
  })

  it('rejects empty files or invalid MIME types before decode', async () => {
    const emptyFile = new File([], 'empty.jpg', { type: 'image/jpeg' })
    await expect(compressImage(emptyFile)).rejects.toThrow('الملف فارغ أو غير موجود')

    const invalidMimeFile = new File(['content'], 'text.txt', { type: 'text/plain' })
    await expect(compressImage(invalidMimeFile)).rejects.toThrow('نوع ملف الصورة غير صالح')
  })

  it('validates options parameter ranges correctly', async () => {
    const validFile = new File(['content'], 'image.jpg', { type: 'image/jpeg' })
    await expect(compressImage(validFile, { maxWidth: -100 })).rejects.toThrow('أقصى عرض للصورة غير صالح')
    await expect(compressImage(validFile, { maxHeight: 0 })).rejects.toThrow('أقصى ارتفاع للصورة غير صالح')
    await expect(compressImage(validFile, { quality: 1.5 })).rejects.toThrow('جودة ضغط الصورة غير صالحة')
    await expect(compressImage(validFile, { maxCompressedSize: 3 * 1024 * 1024 })).rejects.toThrow('الحد الأقصى لحجم الصورة بعد الضغط غير صالح')
    await expect(compressImage(validFile, { maxCompressedSize: 1000.5 })).rejects.toThrow('الحد الأقصى لحجم الصورة بعد الضغط غير صالح')
  })

  it('validates dimensions correctly (width > 0, height > 0 and limits)', () => {
    expect(() => validateImageDimensions(0, 100)).toThrow('أبعاد الصورة غير صالحة')
    expect(() => validateImageDimensions(100, -10)).toThrow('أبعاد الصورة غير صالحة')
    expect(() => validateImageDimensions(9000, 100)).toThrow('أبعاد الصورة تتجاوز الحد الأقصى')
    expect(() => validateImageDimensions(5000, 5000)).toThrow('عدد بكسلات الصورة كبير جداً')
  })

  it('does NOT fallback on decode errors', async () => {
    const file = new File(['bad image content'], 'image.jpg', { type: 'image/jpeg' })

    // Simulate Image.onerror triggering decode failure
    const mockImageClass = class {
      onload: (() => void) | null = null
      onerror: ((err: ErrorEvent) => void) | null = null
      src = ''
      constructor() {
        setTimeout(() => {
          if (this.onerror) {
            this.onerror(new ErrorEvent('error', { message: 'Decode error' }))
          }
        }, 10)
      }
    }
    Object.defineProperty(globalThis, 'Image', {
      value: mockImageClass as unknown as typeof Image,
      configurable: true,
      writable: true
    })

    await expect(compressImage(file)).rejects.toThrow('فشل تحميل وفك ترميز الصورة')
  })

  it('does NOT fallback on invalid image dimensions', async () => {
    const file = new File(['image content'], 'image.jpg', { type: 'image/jpeg' })

    // Simulate Image returning invalid dimensions
    const mockImageClass = class {
      onload: (() => void) | null = null
      onerror: ((err: ErrorEvent) => void) | null = null
      src = ''
      width = 9000 // exceeds max dimension
      height = 500
      constructor() {
        setTimeout(() => {
          if (this.onload) this.onload()
        }, 10)
      }
    }
    Object.defineProperty(globalThis, 'Image', {
      value: mockImageClass as unknown as typeof Image,
      configurable: true,
      writable: true
    })

    await expect(compressImage(file)).rejects.toThrow('أبعاد الصورة تتجاوز الحد الأقصى')
  })

  it('canvas failure fallback logic: allowed if <= 2MB, throws if > 2MB', async () => {
    // 1. Original file size <= 2MB (allowed fallback)
    const smallFile = new File(['smallcontent'], 'image.jpg', { type: 'image/jpeg' })

    const mockImageClass = class {
      onload: (() => void) | null = null
      onerror: ((err: ErrorEvent) => void) | null = null
      src = ''
      width = 500
      height = 500
      constructor() {
        setTimeout(() => {
          if (this.onload) this.onload()
        }, 10)
      }
    }
    Object.defineProperty(globalThis, 'Image', {
      value: mockImageClass as unknown as typeof Image,
      configurable: true,
      writable: true
    })

    // Force canvas context to return null
    const originalCreateElementFn = document.createElement
    const createElementSpy = vi.spyOn(document, 'createElement').mockImplementation((tagName) => {
      if (tagName === 'canvas') {
        return {
          width: 0,
          height: 0,
          getContext: () => null // force failure
        } as unknown as HTMLCanvasElement
      }
      return originalCreateElementFn.call(document, tagName)
    })

    try {
      const res = await compressImage(smallFile)
      expect(res.blob).toBe(smallFile) // Fallback succeeded
    } finally {
      createElementSpy.mockRestore()
    }

    // 2. Original file size > 2MB (fallback rejected)
    const largeFile = new File([new ArrayBuffer(3 * 1024 * 1024)], 'image.jpg', { type: 'image/jpeg' })
    const createElementSpy2 = vi.spyOn(document, 'createElement').mockImplementation((tagName) => {
      if (tagName === 'canvas') {
        return {
          width: 0,
          height: 0,
          getContext: () => null // force failure
        } as unknown as HTMLCanvasElement
      }
      return originalCreateElementFn.call(document, tagName)
    })

    try {
      // Should reject because file is too big to fallback
      await expect(compressImage(largeFile, { maxCompressedSize: 2 * 1024 * 1024 })).rejects.toThrow(
        'فشل معالجة الصورة باستخدام Canvas وحجم الملف الأصلي يتجاوز الحد المسموح به'
      )
    } finally {
      createElementSpy2.mockRestore()
    }
  })

  it('handles canvas zero-size blob: falls back to small original file', async () => {
    const smallFile = new File(['small content'], 'image.jpg', { type: 'image/jpeg' })

    const mockImageClass = class {
      onload: (() => void) | null = null
      onerror: ((err: ErrorEvent) => void) | null = null
      src = ''
      width = 500
      height = 500
      constructor() {
        setTimeout(() => {
          if (this.onload) this.onload()
        }, 10)
      }
    }
    Object.defineProperty(globalThis, 'Image', {
      value: mockImageClass as unknown as typeof Image,
      configurable: true,
      writable: true
    })

    const originalCreateElementFn = document.createElement
    const createElementSpy = vi.spyOn(document, 'createElement').mockImplementation((tagName) => {
      if (tagName === 'canvas') {
        return {
          width: 500,
          height: 500,
          getContext: () => ({
            drawImage: () => {}
          }),
          toBlob: (cb: (b: Blob | null) => void) => {
            cb(new Blob([], { type: 'image/jpeg' })) // size is 0
          }
        } as unknown as HTMLCanvasElement
      }
      return originalCreateElementFn.call(document, tagName)
    })

    try {
      // Small file should fallback successfully
      const res = await compressImage(smallFile)
      expect(res.blob).toBe(smallFile)
    } finally {
      createElementSpy.mockRestore()
    }
  })

  it('handles canvas zero-size blob: rejects fallback if original file exceeds maxCompressedSize', async () => {
    const largeFile = new File([new ArrayBuffer(3 * 1024 * 1024)], 'image.jpg', { type: 'image/jpeg' })

    const mockImageClass = class {
      onload: (() => void) | null = null
      onerror: ((err: ErrorEvent) => void) | null = null
      src = ''
      width = 500
      height = 500
      constructor() {
        setTimeout(() => {
          if (this.onload) this.onload()
        }, 10)
      }
    }
    Object.defineProperty(globalThis, 'Image', {
      value: mockImageClass as unknown as typeof Image,
      configurable: true,
      writable: true
    })

    const originalCreateElementFn = document.createElement
    const createElementSpy = vi.spyOn(document, 'createElement').mockImplementation((tagName) => {
      if (tagName === 'canvas') {
        return {
          width: 500,
          height: 500,
          getContext: () => ({
            drawImage: () => {}
          }),
          toBlob: (cb: (b: Blob | null) => void) => {
            cb(new Blob([], { type: 'image/jpeg' })) // size is 0
          }
        } as unknown as HTMLCanvasElement
      }
      return originalCreateElementFn.call(document, tagName)
    })

    try {
      // Large file should throw because it exceeds limit
      await expect(compressImage(largeFile, { maxCompressedSize: 2 * 1024 * 1024 })).rejects.toThrow(
        'فشل معالجة الصورة باستخدام Canvas وحجم الملف الأصلي يتجاوز الحد المسموح به'
      )
    } finally {
      createElementSpy.mockRestore()
    }
  })
})
