import { supabase } from '@/lib/supabase/client'
import type { CompanySetting } from '@/lib/types/auth'

/**
 * جلب كل الإعدادات (أو فئة محددة)
 */
export async function getSettings(category?: string) {
  let query = supabase
    .from('company_settings')
    .select('*')
    .order('category')
    .order('key')

  if (category) {
    query = query.eq('category', category)
  }

  const { data, error } = await query
  if (error) throw error
  return data as CompanySetting[]
}

/**
 * تحديث مجموعة إعدادات دفعة واحدة
 */
export async function updateSettings(updates: { key: string; value: string }[]) {
  // Supabase doesn't support batch upsert easily, so we do individual updates
  const errors: string[] = []

  for (const { key, value } of updates) {
    const { error } = await supabase
      .from('company_settings')
      .update({
        value,
        updated_at: new Date().toISOString(),
      })
      .eq('key', key)

    if (error) errors.push(`${key}: ${error.message}`)
  }

  if (errors.length > 0) {
    throw new Error(`فشل تحديث الإعدادات التالية:\n${errors.join('\n')}`)
  }
}

/**
 * جلب إعداد واحد بالمفتاح
 */
export async function getSetting(key: string): Promise<string | null> {
  const { data, error } = await supabase
    .from('company_settings')
    .select('value')
    .eq('key', key)
    .single()

  if (error) return null
  return data?.value ?? null
}

/**
 * جلب سجل التدقيق
 */
export async function getAuditLogs(params?: {
  search?: string
  action?: string
  entityType?: string
  page?: number
  pageSize?: number
}) {
  const page = params?.page || 1
  const pageSize = params?.pageSize || 25
  const from = (page - 1) * pageSize
  const to = from + pageSize - 1

  let query = supabase
    .from('audit_logs')
    .select('*', { count: 'estimated' })
    .order('created_at', { ascending: false })
    .range(from, to)

  if (params?.action) {
    query = query.eq('action', params.action)
  }
  if (params?.entityType) {
    query = query.eq('entity_type', params.entityType)
  }

  const { data: logs, error, count } = await query
  if (error) throw error

  // جلب بيانات المنفذين
  const userIds = [...new Set((logs || []).map(l => l.user_id).filter(Boolean))]
  let profilesMap = new Map<string, { full_name: string; avatar_url: string | null }>()

  if (userIds.length > 0) {
    const { data: profiles } = await supabase
      .from('profiles')
      .select('id, full_name, avatar_url')
      .in('id', userIds)
    for (const p of profiles || []) {
      profilesMap.set(p.id, p)
    }
  }

  const enriched = (logs || []).map(log => ({
    ...log,
    profile: log.user_id ? profilesMap.get(log.user_id) || null : null,
  }))

  return {
    data: enriched,
    count: count || 0,
    page,
    pageSize,
    totalPages: Math.ceil((count || 0) / pageSize),
  }
}

