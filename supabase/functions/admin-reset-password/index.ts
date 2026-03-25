// @ts-nocheck — This file runs in Deno runtime, not Node.js
// supabase/functions/admin-reset-password/index.ts
// Edge Function: إعادة تعيين كلمة مرور مستخدم
// يتطلب صلاحية auth.users.reset_password

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return Response.json({ error: 'غير مصرح' }, { status: 401, headers: corsHeaders })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    // التحقق من هوية المستدعي
    const { data: { user: caller }, error: authErr } = await callerClient.auth.getUser()
    if (authErr || !caller) {
      return Response.json({ error: 'جلسة غير صالحة' }, { status: 401, headers: corsHeaders })
    }

    // التحقق من الصلاحية
    const { data: hasPermission } = await adminClient.rpc('check_permission', {
      p_user_id: caller.id,
      p_permission: 'auth.users.reset_password',
    })

    if (!hasPermission) {
      return Response.json(
        { error: 'ليس لديك صلاحية إعادة تعيين كلمات المرور' },
        { status: 403, headers: corsHeaders }
      )
    }

    // قراءة البيانات
    const { userId, newPassword } = await req.json()

    if (!userId || !newPassword) {
      return Response.json(
        { error: 'مطلوب: userId و newPassword' },
        { status: 400, headers: corsHeaders }
      )
    }

    if (typeof newPassword !== 'string' || newPassword.length < 8) {
      return Response.json(
        { error: 'كلمة المرور يجب أن تكون 8 أحرف على الأقل' },
        { status: 400, headers: corsHeaders }
      )
    }

    // منع إعادة تعيين كلمة المرور الذاتية
    if (userId === caller.id) {
      return Response.json(
        { error: 'لا يمكنك إعادة تعيين كلمة المرور الخاصة بك من هنا' },
        { status: 400, headers: corsHeaders }
      )
    }

    // التحقق من وجود المستخدم المستهدف
    const { data: targetProfile } = await adminClient
      .from('profiles')
      .select('id, full_name')
      .eq('id', userId)
      .single()

    if (!targetProfile) {
      return Response.json(
        { error: 'المستخدم المستهدف غير موجود' },
        { status: 404, headers: corsHeaders }
      )
    }

    // التحقق من هرمية الأدوار — لا يمكن إعادة تعيين كلمة مرور لمستخدم بدور أعلى أو مساوٍ
    const { data: callerGrade } = await adminClient.rpc('get_user_max_grade', {
      p_user_id: caller.id,
    })
    const { data: targetGrade } = await adminClient.rpc('get_user_max_grade', {
      p_user_id: userId,
    })

    if ((targetGrade ?? 0) >= (callerGrade ?? 0)) {
      return Response.json(
        { error: 'لا يمكنك إعادة تعيين كلمة مرور مستخدم بمستوى يساوي أو يفوق مستواك' },
        { status: 403, headers: corsHeaders }
      )
    }

    // إعادة تعيين كلمة المرور
    const { error: resetError } = await adminClient.auth.admin.updateUserById(userId, {
      password: newPassword,
    })

    if (resetError) {
      return Response.json(
        { error: resetError.message },
        { status: 400, headers: corsHeaders }
      )
    }

    // تسجيل العملية في audit_logs
    await adminClient.from('audit_logs').insert({
      user_id: caller.id,
      action: 'password_reset',
      entity_type: 'profiles',
      entity_id: userId,
      new_data: {
        target_user: targetProfile.full_name,
        performed_by: caller.id,
      },
    })

    return Response.json(
      { success: true },
      { status: 200, headers: corsHeaders }
    )
  } catch (err) {
    console.error('admin-reset-password error:', err)
    return Response.json(
      { error: err instanceof Error ? err.message : 'خطأ غير متوقع' },
      { status: 500, headers: corsHeaders }
    )
  }
})
