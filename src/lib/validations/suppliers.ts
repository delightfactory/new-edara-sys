import { z } from 'zod'

/**
 * Zod schema — تحقق من بيانات المورد
 * يُستخدم في SupplierFormPage مع react-hook-form
 */
export const supplierSchema = z.object({
  name: z.string().min(2, 'اسم المورد مطلوب (حرفان على الأقل)').max(200),
  phone: z.string().max(30).optional().nullable(),
  mobile: z.string().max(30).optional().nullable(),
  email: z
    .string()
    .email('بريد إلكتروني غير صحيح')
    .optional()
    .nullable()
    .or(z.literal('')),
  address: z.string().max(500).optional().nullable(),
  tax_number: z.string().max(30).optional().nullable(),
  commercial_register: z.string().max(50).optional().nullable(),
  payment_terms: z.enum(['cash', 'credit', 'mixed']).default('cash'),
  credit_limit: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .min(0, 'الحد الائتماني لا يمكن أن يكون سالباً')
    .default(0),
  credit_days: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .int('يجب أن يكون عدداً صحيحاً')
    .min(0, 'لا يمكن أن يكون سالباً')
    .default(0),
  opening_balance: z
    .number({ invalid_type_error: 'يجب إدخال رقم' })
    .default(0),
  notes: z.string().max(1000).optional().nullable(),
})

export type SupplierFormData = z.infer<typeof supplierSchema>
