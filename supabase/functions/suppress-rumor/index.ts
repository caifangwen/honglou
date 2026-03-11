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
      .select('id, qi_points, role_class')
      .eq('auth_uid', user.id)
      .single()

    if (playerError || !player) throw new Error('Player not found')

    // 2. 获取流言
    const { data: rumor, error: rumorError } = await supabase
      .from('rumors')
      .select('*')
      .eq('id', rumor_id)
      .single()

    if (rumorError || !rumor) throw new Error('Rumor not found')

    // 3. 校验逻辑
    // 只能压制针对自己的流言，且必须在阶段 1
    if (rumor.target_uid !== player.id) {
      return new Response(JSON.stringify({ error: 'not_the_target' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 403,
      })
    }

    if (rumor.stage !== 1) {
      return new Response(JSON.stringify({ error: 'cannot_suppress_after_stage1' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    if (player.qi_points < 10) {
      return new Response(JSON.stringify({ error: 'insufficient_qi_points' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // 4. 执行压制
    const { error: updateError } = await supabase
      .from('rumors')
      .update({
        is_suppressed: true,
        suppressed_by: player.id,
        suppressed_at: new Date().toISOString(),
        suppress_method: 'self_suppress'
      })
      .eq('id', rumor_id)

    if (updateError) throw updateError

    // 扣除气数
    await supabase
      .from('players')
      .update({ qi_points: player.qi_points - 10 })
      .eq('id', player.id)

    // 记录事件
    await supabase
      .from('rumor_events')
      .insert({
        rumor_id: rumor_id,
        actor_uid: player.id,
        event_type: 'self_suppressed',
        event_data: { cost_qi: 10 }
      })

    return new Response(JSON.stringify({ success: true }), {
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
