/**
 * rewardRules.ts — Source of Truth لقواعد إعداد المكافأة
 *
 * يُطابق حرفياً دالة is_valid_reward_config() في قاعدة البيانات.
 * أي تغيير في منطق DB يجب أن يُعكس هنا بالتزامن.
 *
 * قواعد is_valid_reward_config():
 * 1. reward_type = null → صحيح دائماً (pool_basis يجب أن يكون null)
 * 2. reward_type = 'fixed' → pool_basis يجب أن يكون null دائماً
 * 3. reward_type = 'percentage':
 *    - مسموح فقط إذا كانت typeCategory = 'financial' أو typeCode = 'upgrade_value'
 *    - pool_basis إلزامي (non-null)
 *    - upgrade_value → sales_value فقط
 *    - collection → collection_value فقط
 *    - collection_value → مسموح فقط مع collection
 *    - sales_value (financial غير collection) → sales_value فقط
 */

export type RewardType = 'fixed' | 'percentage' | ''
export type PoolBasis  = 'sales_value' | 'collection_value' | ''

/** هل يُسمح باختيار percentage لهذا النوع؟ */
export function allowsPercentageReward(typeCategory: string, typeCode: string): boolean {
  return typeCategory === 'financial' || typeCode === 'upgrade_value'
}

/**
 * ما هو وعاء الحساب المقيَّد تلقائياً للنوع؟
 * - null = اختيار حر (بين الخيارات المسموح بها)
 * - 'sales_value' | 'collection_value' = مقيَّد تلقائياً
 */
export function getLockedPoolBasis(typeCode: string): 'sales_value' | 'collection_value' | null {
  if (typeCode === 'collection')    return 'collection_value'
  if (typeCode === 'upgrade_value') return 'sales_value'
  // كل النوع financial الأخرى (sales_value, ...) → sales_value فقط مسموح
  // لأن collection_value ممنوع إلا مع collection
  return 'sales_value' // ← مقيَّد تلقائياً لأن collection_value محظور على غير collection
}

/**
 * ما هي خيارات pool_basis المسموح بها لهذا النوع مع percentage؟
 * تُستخدم لبناء قائمة الـ select.
 */
export function getAllowedPoolBasisOptions(typeCode: string): { value: PoolBasis; label: string }[] {
  if (typeCode === 'collection') {
    return [{ value: 'collection_value', label: 'إجمالي التحصيلات' }]
  }
  if (typeCode === 'upgrade_value') {
    return [{ value: 'sales_value', label: 'إجمالي المبيعات' }]
  }
  // financial أخرى (sales_value, ...) — collection_value محظور إلا مع collection
  return [{ value: 'sales_value', label: 'إجمالي المبيعات' }]
}

/**
 * التحقق من صحة التركيبة (Frontend-side mirror لـ is_valid_reward_config)
 *
 * يُعيد null إذا كانت التركيبة صحيحة، أو رسالة الخطأ إذا كانت خاطئة.
 */
export function validateRewardConfig(
  typeCategory: string,
  typeCode: string,
  rewardType: RewardType | null,
  poolBasis: PoolBasis | null
): string | null {
  const rt = rewardType    || null
  const pb = poolBasis     || null

  // null reward = صحيح دائماً (pool_basis يجب null)
  if (rt === null) {
    if (pb !== null) return 'وعاء الحساب يجب أن يكون فارغاً بدون مكافأة'
    return null
  }

  // fixed → pool_basis يجب null
  if (rt === 'fixed') {
    if (pb !== null) return 'المكافأة المقطوعة لا تتطلب وعاء حساب'
    return null
  }

  // percentage
  if (rt === 'percentage') {
    // مسموح فقط للمالية وupgrade_value
    if (typeCategory !== 'financial' && typeCode !== 'upgrade_value') {
      return 'المكافأة النسبية مسموحة فقط للأهداف المالية وأهداف رفع قيمة العميل'
    }

    // pool_basis إلزامي
    if (!pb) {
      return 'وعاء الحساب إلزامي عند اختيار المكافأة النسبية'
    }

    // upgrade_value → sales_value فقط
    if (typeCode === 'upgrade_value' && pb !== 'sales_value') {
      return 'هدف رفع قيمة العميل يدعم فقط وعاء إجمالي المبيعات'
    }

    // collection → collection_value فقط
    if (typeCode === 'collection' && pb !== 'collection_value') {
      return 'هدف التحصيل يدعم فقط وعاء إجمالي التحصيلات'
    }

    // collection_value → مسموح فقط مع collection
    if (pb === 'collection_value' && typeCode !== 'collection') {
      return 'وعاء التحصيلات مسموح فقط لأهداف التحصيل'
    }
  }

  return null
}

/**
 * نُوحِّد pool_basis مع rewardType تلقائياً:
 * - إذا تغيّر rewardType إلى fixed/null → pool_basis يُصبح ''
 * - إذا كان percentage + locked basis → يُعيّن تلقائياً
 */
export function normalizePoolBasis(
  typeCode: string,
  rewardType: RewardType,
  currentPoolBasis: PoolBasis
): PoolBasis {
  if (!rewardType || rewardType === 'fixed') return ''

  // percentage → للأنواع المقيَّدة تلقائياً
  const locked = getLockedPoolBasis(typeCode)
  if (locked) return locked

  // اختيار حر — احتفظ بالقيمة الحالية إن كانت صالحة
  return currentPoolBasis
}
