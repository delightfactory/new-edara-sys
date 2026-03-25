import { z } from 'zod'

/**
 * Zod schema — تحقق من بيانات العميل
 * يُستخدم في CustomerFormPage مع react-hook-form
 */
export const customerSchema = z.object({
  name: z.string().min(2, 'اسم العميل مطلوب (حرفان على الأقل)').max(200),
  type: z.enum(['retail', 'wholesale', 'distributor']).default('retail'),
  governorate_id: z.string().uuid().nullable().optional(),
  city_id: z.string().uuid().nullable().optional(),
  area_id: z.string().uuid().nullable().optional(),
  address: z.string().max(500).optional().nullable(),
  phone: z.string().max(30).optional().nullable(),
  mobile: z.string().max(30).optional().nullable(),
  email: z
    .string()
    .email('بريد إلكتروني غير صحيح')
    .optional()
    .nullable()
    .or(z.literal('')),
  tax_number: z.string().max(30).optional().nullable(),
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
  price_list_id: z.string().uuid().nullable().optional(),
  assigned_rep_id: z.string().uuid().nullable().optional(),
  notes: z.string().max(1000).optional().nullable(),
})

export type CustomerFormData = z.infer<typeof customerSchema>
