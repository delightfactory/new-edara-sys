export function validateOriginalFile(file: File, maxSizeBytes = 10 * 1024 * 1024): void {
  if (!file || file.size === 0) {
    throw new Error('الملف فارغ أو غير موجود');
  }
  if (file.size > maxSizeBytes) {
    throw new Error('حجم الصورة الأصلي يتجاوز الحد الأقصى المسموح به (10 ميجابايت)');
  }
  const allowedMimeTypes = ['image/jpeg', 'image/png'];
  if (!allowedMimeTypes.includes(file.type)) {
    throw new Error('نوع ملف الصورة غير صالح. يجب أن تكون الصورة من نوع JPEG أو PNG');
  }
}

export function validateImageDimensions(
  width: number,
  height: number,
  maxDimension = 8192,
  maxPixels = 24 * 1000 * 1000
): void {
  if (width <= 0 || height <= 0) {
    throw new Error('أبعاد الصورة غير صالحة (يجب أن تكون أكبر من صفر)');
  }
  if (width > maxDimension || height > maxDimension) {
    throw new Error(`أبعاد الصورة تتجاوز الحد الأقصى المسموح به (${maxDimension} بكسل)`);
  }
  if (width * height > maxPixels) {
    throw new Error('عدد بكسلات الصورة كبير جداً، يرجى اختيار صورة أصغر');
  }
}

export interface CompressedImageResult {
  blob: Blob;
  mimeType: string;
  extension: string;
  sizeBytes: number;
  checksum: string;
}

export async function compressImage(
  file: File,
  options: {
    maxWidth?: number;
    maxHeight?: number;
    quality?: number;
    maxCompressedSize?: number;
  } = {}
): Promise<CompressedImageResult> {
  const {
    maxWidth = 1200,
    maxHeight = 1200,
    quality = 0.8,
    maxCompressedSize = 2 * 1024 * 1024 // 2MB
  } = options;

  if (maxWidth !== undefined && (typeof maxWidth !== 'number' || maxWidth <= 0 || !Number.isInteger(maxWidth) || isNaN(maxWidth))) {
    throw new Error('أقصى عرض للصورة غير صالح');
  }
  if (maxHeight !== undefined && (typeof maxHeight !== 'number' || maxHeight <= 0 || !Number.isInteger(maxHeight) || isNaN(maxHeight))) {
    throw new Error('أقصى ارتفاع للصورة غير صالح');
  }
  if (quality !== undefined && (typeof quality !== 'number' || quality < 0.1 || quality > 1.0 || isNaN(quality))) {
    throw new Error('جودة ضغط الصورة غير صالحة');
  }
  if (maxCompressedSize !== undefined && (typeof maxCompressedSize !== 'number' || maxCompressedSize <= 0 || !Number.isInteger(maxCompressedSize) || isNaN(maxCompressedSize) || maxCompressedSize > 2 * 1024 * 1024)) {
    throw new Error('الحد الأقصى لحجم الصورة بعد الضغط غير صالح (يجب أن يكون رقماً موجباً لا يتجاوز 2 ميجابايت)');
  }

  validateOriginalFile(file);

  const readBlobAsArrayBuffer = async (blob: Blob): Promise<ArrayBuffer> => {
    if (typeof blob.arrayBuffer === 'function') {
      return blob.arrayBuffer();
    }

    return new Promise<ArrayBuffer>((resolve, reject) => {
      const reader = new FileReader();
      reader.onerror = () => reject(new Error('فشل قراءة بيانات الصورة لحساب البصمة'));
      reader.onload = () => {
        if (reader.result instanceof ArrayBuffer) {
          resolve(reader.result);
          return;
        }
        reject(new Error('تعذر تحويل بيانات الصورة إلى مصفوفة ثنائية'));
      };
      reader.readAsArrayBuffer(blob);
    });
  };

  const calculateChecksum = async (blob: Blob): Promise<string> => {
    const buffer = await readBlobAsArrayBuffer(blob);
    const hashBuffer = await crypto.subtle.digest('SHA-256', buffer);
    const hashArray = Array.from(new Uint8Array(hashBuffer));
    return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
  };

  const loadImage = (url: string): Promise<HTMLImageElement> => {
    return new Promise((resolve, reject) => {
      const img = new Image();
      img.onload = () => resolve(img);
      img.onerror = () => reject(new Error('فشل تحميل وفك ترميز الصورة'));
      img.src = url;
    });
  };

  const objectUrl = URL.createObjectURL(file);
  try {
    const img = await loadImage(objectUrl);
    validateImageDimensions(img.width, img.height);

    let width = img.width;
    let height = img.height;
    if (width > maxWidth || height > maxHeight) {
      const ratio = Math.min(maxWidth / width, maxHeight / height);
      width = Math.round(width * ratio);
      height = Math.round(height * ratio);
    }

    let compressedBlob: Blob | null = null;
    try {
      const canvas = document.createElement('canvas');
      canvas.width = width;
      canvas.height = height;
      const ctx = canvas.getContext('2d');
      if (!ctx) {
        throw new Error('canvas_context_failed');
      }
      ctx.drawImage(img, 0, 0, width, height);

      compressedBlob = await new Promise<Blob | null>((resolve) => {
        canvas.toBlob((b) => resolve(b), 'image/jpeg', quality);
      });

      if (!compressedBlob || compressedBlob.size === 0) {
        throw new Error('canvas_blob_failed');
      }
    } catch (canvasErr) {
      // Fallback is allowed ONLY if Canvas fails after successful decode and validation
      if (file.size <= maxCompressedSize) {
        const mimeType = file.type;
        const extension = mimeType === 'image/png' ? 'png' : 'jpg';
        const checksum = await calculateChecksum(file);
        return {
          blob: file,
          mimeType,
          extension,
          sizeBytes: file.size,
          checksum
        };
      }
      throw new Error('فشل معالجة الصورة باستخدام Canvas وحجم الملف الأصلي يتجاوز الحد المسموح به');
    }

    if (compressedBlob.size > maxCompressedSize) {
      throw new Error('حجم الصورة بعد الضغط يتجاوز الحد المسموح به');
    }

    const checksum = await calculateChecksum(compressedBlob);

    return {
      blob: compressedBlob,
      mimeType: 'image/jpeg',
      extension: 'jpg',
      sizeBytes: compressedBlob.size,
      checksum
    };
  } finally {
    URL.revokeObjectURL(objectUrl);
  }
}
