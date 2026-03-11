import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { supabase, corsHeaders } from '../_shared/supabaseClient.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const authHeader = req.headers.get('Authorization')!
    const { data: { user }, error: authError } = await supabase.auth.getUser(authHeader.replace('Bearer ', ''))
    
    if (authError || !user) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const body = await req.json()
    const { rumor_id } = body

    // 1. 获取当前玩家
    const { data: player, error: playerError } = await supabase
      .from('players')
      .select('id, stamina, role_class')
      .eq('auth_uid', user.id)
      .single()

    if (playerError || !player) throw new Error('Player not found')

    // 2. 校验角色是否为管家
    if (player.role_class !== 'steward') {
      return new Response(JSON.stringify({ error: 'only_steward_can_quell' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    // 3. 获取流言
    const { data: rumor, error: rumorError } = await supabase
      .from('rumors')
      .select('*')
      .eq('id', rumor_id)
      .single()

    if (rumorError || !rumor) throw new Error('Rumor not found')

    // 4. 校验逻辑
    if (rumor.stage !== 2) {
      return new Response(JSON.stringify({ error: 'can_only_quell_in_stage2' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    if (player.stamina < 2) {
      return new Response(JSON.stringify({ error: 'insufficient_stamina' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // 5. 执行平息
    const { error: updateError } = await supabase
      .from('rumors')
      .update({
        is_suppressed: true,
        suppressed_by: player.id,
        suppressed_at: new Date().toISOString(),
        suppress_method: 'steward_quell'
      })
      .eq('id', rumor_id)

    if (updateError) throw updateError

    // 扣除精力
    await supabase
      .from('players')
      .update({ stamina: player.stamina - 2 })
      .eq('id', player.id)

    // 记录事件
    await supabase
      .from('rumor_events')
      .insert({
        rumor_id: rumor_id,
        actor_uid: player.id,
        event_type: 'steward_quelled',
        event_data: { cost_stamina: 2 }
      })

    // 通知目标玩家
    await supabase
      .from('messages')
      .insert({
        game_id: rumor.game_id,
        receiver_uid: rumor.target_uid,
        message_type: 'system',
        content: '幸有管家出面，那流言已被压下，但你欠了一份情。'
      })

    return new Response(JSON.stringify({ 
      success: true,
      intervention_logged: true 
    }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})
