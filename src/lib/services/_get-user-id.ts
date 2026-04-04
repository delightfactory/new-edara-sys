/**
 * getAuthUserId — helper موحّد لجلب current user id
 *
 * أولوية الجلب (من الأسرع إلى fallback):
 *  1. useAuthStore.getState().profile?.id  ← من الذاكرة، بدون شبكة
 *  2. supabase.auth.getSession()           ← يقرأ من localStorage cache
 *  3. throw Error واضح
 *
 * ممنوع استخدام supabase.auth.getUser() هنا —
 * getUser() ترسل طلب HTTP لـ Supabase Auth server في كل استدعاء،
 * وهذا يضيف latency متكرر في hot mutation paths.
 *
 * الأمان: RLS في Supabase هي الحارس الحقيقي على مستوى قاعدة البيانات.
 * أي userId مُمرَّر لـ RPC أو INSERT سيُتحقق منه بواسطة auth.uid() داخل DB.
 */
import { useAuthStore } from '@/stores/auth-store'
import { supabase } from '@/lib/supabase/client'

export async function getAuthUserId(): Promise<string> {
  // Priority 1: من الـ store (في الذاكرة — بدون شبكة على الإطلاق)
  const profileId = useAuthStore.getState().profile?.id
  if (profileId) return profileId

  // Priority 2: من session cache في localStorage (لا يُرسل طلب لـ Auth server)
  const { data: { session } } = await supabase.auth.getSession()
  if (session?.user?.id) return session.user.id

  throw new Error('يجب تسجيل الدخول')
}
