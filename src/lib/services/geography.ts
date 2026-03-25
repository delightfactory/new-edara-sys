import { supabase } from '@/lib/supabase/client'
import type { Governorate, City, Area, Branch, BranchInput } from '@/lib/types/master-data'

// ============================================================
// Geography — المحافظات والمدن والمناطق
// ============================================================

/**
 * جلب كل المحافظات مرتبة
 */
export async function getGovernorates() {
  const { data, error } = await supabase
    .from('governorates')
    .select('*')
    .order('sort_order')
  if (error) throw error
  return data as Governorate[]
}

/**
 * جلب مدن محافظة معينة (أو كل المدن)
 */
export async function getCities(governorateId?: string) {
  let query = supabase
    .from('cities')
    .select('*, governorate:governorates(id, name, name_en)')
    .order('sort_order')

  if (governorateId) {
    query = query.eq('governorate_id', governorateId)
  }

  const { data, error } = await query
  if (error) throw error
  return data as City[]
}

/**
 * جلب مناطق مدينة معينة
 */
export async function getAreas(cityId: string) {
  const { data, error } = await supabase
    .from('areas')
    .select('*')
    .eq('city_id', cityId)
    .order('name')
  if (error) throw error
  return data as Area[]
}

/**
 * إنشاء منطقة جديدة
 */
export async function createArea(cityId: string, name: string) {
  const { data, error } = await supabase
    .from('areas')
    .insert({ city_id: cityId, name })
    .select()
    .single()
  if (error) throw error
  return data as Area
}

/**
 * حذف منطقة
 */
export async function deleteArea(id: string) {
  const { error } = await supabase
    .from('areas')
    .delete()
    .eq('id', id)
  if (error) throw error
}

// ============================================================
// Branches — الفروع
// ============================================================

/**
 * جلب كل الفروع مع بيانات المدينة والمدير
 */
export async function getBranches() {
  const { data, error } = await supabase
    .from('branches')
    .select(`
      *,
      city:cities(id, name, governorate:governorates(id, name)),
      manager:profiles!branches_manager_id_fkey(id, full_name)
    `)
    .order('created_at', { ascending: false })
  if (error) throw error
  return data as Branch[]
}

/**
 * جلب فرع واحد
 */
export async function getBranch(id: string) {
  const { data, error } = await supabase
    .from('branches')
    .select(`
      *,
      city:cities(id, name, governorate:governorates(id, name)),
      manager:profiles!branches_manager_id_fkey(id, full_name)
    `)
    .eq('id', id)
    .single()
  if (error) throw error
  return data as Branch
}

/**
 * إنشاء فرع
 */
export async function createBranch(input: BranchInput) {
  const { data, error } = await supabase
    .from('branches')
    .insert(input)
    .select()
    .single()
  if (error) throw error
  return data as Branch
}

/**
 * تحديث فرع
 */
export async function updateBranch(id: string, input: Partial<BranchInput>) {
  const { data, error } = await supabase
    .from('branches')
    .update(input)
    .eq('id', id)
    .select()
    .single()
  if (error) throw error
  return data as Branch
}
