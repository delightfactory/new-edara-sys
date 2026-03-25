// @ts-nocheck — This file runs in Deno runtime, not Node.js
// supabase/functions/create-user/index.ts
// Edge Function: إنشاء مستخدم جديد
// يتطلب صلاحية auth.users.create

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  // CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response(null, { headers: corsHeaders })
  }

  try {
    // 1. التحقق من التوكن
    const authHeader = req.headers.get('Authorization')
    if (!authHeader) {
      return Response.json({ error: 'غير مصرح' }, { status: 401, headers: corsHeaders })
    }

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    // Client بصلاحيات المستدعي (للتحقق من هويته)
    const callerClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    })

    // Admin client (service_role — لا يُكشف أبداً للعميل)
    const adminClient = createClient(supabaseUrl, serviceRoleKey)

    // 2. التحقق من هوية المستدعي
    const { data: { user: caller }, error: authErr } = await callerClient.auth.getUser()
    if (authErr || !caller) {
      return Response.json({ error: 'جلسة غير صالحة' }, { status: 401, headers: corsHeaders })
    }

    // 3. التحقق من صلاحية المستدعي
    const { data: hasPermission } = await adminClient.rpc('check_permission', {
      p_user_id: caller.id,
      p_permission: 'auth.users.create',
    })

    if (!hasPermission) {
      return Response.json(
        { error: 'ليس لديك صلاحية إنشاء مستخدمين' },
        { status: 403, headers: corsHeaders }
      )
    }

    // 4. قراءة بيانات المستخدم الجديد
    const body = await req.json()
    const { full_name, email, password, phone, role_ids } = body

    // التحقق من البيانات المطلوبة
    if (!full_name?.trim() || !email?.trim() || !password) {
      return Response.json(
        { error: 'الاسم والبريد الإلكتروني وكلمة المرور مطلوبين' },
        { status: 400, headers: corsHeaders }
      )
    }

    if (password.length < 8) {
      return Response.json(
        { error: 'كلمة المرور يجب أن تكون 8 أحرف على الأقل' },
        { status: 400, headers: corsHeaders }
      )
    }

    // 5. إنشاء المستخدم في auth.users
    const { data: authData, error: createErr } = await adminClient.auth.admin.createUser({
      email: email.trim().toLowerCase(),
      password,
      email_confirm: true,
      user_metadata: { full_name: full_name.trim() },
    })

    if (createErr) {
      const msg = createErr.message.includes('already been registered')
        ? 'هذا البريد الإلكتروني مسجل بالفعل'
        : createErr.message
      return Response.json({ error: msg }, { status: 400, headers: corsHeaders })
    }

    const newUserId = authData.user.id

    // 6. تحديث الملف الشخصي (أُنشئ تلقائياً عبر trigger handle_new_user)
    await adminClient
      .from('profiles')
      .update({
        full_name: full_name.trim(),
        phone: phone?.trim() || null,
      })
      .eq('id', newUserId)

    // 7. تعيين الأدوار
    if (Array.isArray(role_ids) && role_ids.length > 0) {
      const { error: rolesErr } = await adminClient
        .from('user_roles')
        .insert(
          role_ids.map((rid: string) => ({
            user_id: newUserId,
            role_id: rid,
            assigned_by: caller.id,
          }))
        )

      if (rolesErr) {
        console.error('Role assignment error:', rolesErr)
      }
    }

    // 8. تسجيل العملية في audit_logs
    await adminClient.from('audit_logs').insert({
      user_id: caller.id,
      action: 'create',
      entity_type: 'profiles',
      entity_id: newUserId,
      new_data: { full_name, email, phone, roles: role_ids },
    })

    return Response.json(
      { user_id: newUserId },
      { status: 201, headers: corsHeaders }
    )
  } catch (err) {
    console.error('create-user error:', err)
    return Response.json(
      { error: err instanceof Error ? err.message : 'خطأ غير متوقع' },
      { status: 500, headers: corsHeaders }
    )
  }
})
