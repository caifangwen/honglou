
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { player_uid, steward_uid, action_id, vote_type, game_id } = await req.json()

    // 1. 检查投票资格 (每人限一票)
    const { data: vote, error: vError } = await supabase
      .from('votes')
      .select('*')
      .eq('player_uid', player_uid)
      .eq('action_id', action_id)
      .single()

    if (vote) throw new Error('Already voted')

    // 2. 插入投票记录 (votes 表)
    // 需要创建一个 votes 表来存储投票
    await supabase.from('votes').insert({
      player_uid,
      steward_uid,
      action_id,
      vote_type, // 'fair' | 'unfair'
      game_id
    })

    // 3. 计算投票结果 (实际应由 Cron Job 处理，这里简化为即时统计)
    // 统计 unfair 比例
    const { count: unfairCount } = await supabase.from('votes').select('*', { count: 'exact', head: true }).eq('action_id', action_id).eq('vote_type', 'unfair')
    const { count: totalCount } = await supabase.from('votes').select('*', { count: 'exact', head: true }).eq('action_id', action_id)

    const unfairRate = unfairCount / totalCount
    let prestigeLoss = 0

    if (unfairRate >= 0.4) {
      prestigeLoss = 30 // 更严厉的惩罚
    } else if (unfairRate >= 0.2) {
      prestigeLoss = 15
    }

    if (prestigeLoss > 0) {
      const { data: steward } = await supabase.from('steward_accounts').select('prestige').eq('steward_uid', steward_uid).single()
      if (steward) {
        await supabase.from('steward_accounts').update({ prestige: Math.max(0, steward.prestige - prestigeLoss) }).eq('steward_uid', steward_uid)
      }
    }

    return new Response(JSON.stringify({ success: true, current_unfair_rate: unfairRate }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
