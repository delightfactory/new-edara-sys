import { z } from 'zod'

/**
 * Zod schema — تحقق من بيانات المنتج
 * يُستخدم في ProductFormPage مع react-hook-form
 */
export const productSchema = z.object({
  sku: z.string().min(1, 'كود المنتج مطلوب').max(50),
  name: z.string().min(2, 'اسم المنتج مطلوب (حرفان على الأقل)').max(200),
  barcode: z.string().max(50).optional().nullable(),
  description: z.string().max(1000).optional().nullable(),
  category_id: z.string().uuid().nullable().optional(),
  brand_id: z.string().uuid().nullable().optional(),
  base_unit_id: z.string().uuid('يجب اختيار وحدة القياس'),
  selling_price: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0, 'سعر البيع لا يمكن أن يكون سالباً'),
  cost_price: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0, 'التكلفة لا يمكن أن تكون سالبة')
    .default(0),
  tax_rate: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0, 'لا يمكن أن تكون سالبة')
    .max(100, 'لا يمكن أن تتجاوز 100%')
    .default(0),
  min_stock: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0)
    .default(0),
  max_stock: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0)
    .nullable()
    .optional(),
  reorder_point: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0)
    .nullable()
    .optional(),
  is_active: z.boolean().default(true),
})

export type ProductFormData = z.infer<typeof productSchema>

/**
 * Zod schema — وحدة منتج
 */
export const productUnitSchema = z.object({
  unit_id: z.string().uuid('يجب اختيار الوحدة'),
  conversion_factor: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .positive('معامل التحويل يجب أن يكون أكبر من صفر'),
  barcode: z.string().max(50).optional().nullable(),
  selling_price: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0)
    .nullable()
    .optional(),
})

export type ProductUnitFormData = z.infer<typeof productUnitSchema>
