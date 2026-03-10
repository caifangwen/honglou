
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { actor_id, action_type, target_uid, params, game_id } = await req.json()

    // 1. 获取精力消耗
    const staminaCosts: Record<string, number> = {
      'procurement': 1,
      'assignment': 1,
      'search': 2,
      'advance': 1,
      'suppress_rumor': 2,
      'block_intel': 3
    }
    const cost = staminaCosts[action_type] || 0

    // 2. 精力校验 (本地+服务器双校验)
    const { data: staminaData, error: sError } = await supabase
      .from('steward_stamina')
      .select('*')
      .eq('uid', actor_id)
      .single()

    if (sError || !staminaData) throw new Error('Stamina data not found')

    const now = new Date().getTime()
    const lastRefreshed = new Date(staminaData.last_refresh_at).getTime()
    const elapsedHours = (now - lastRefreshed) / (1000 * 3600)
    const recovered = Math.floor(elapsedHours / 2)
    const currentStamina = Math.min(staminaData.current_stamina + recovered, staminaData.max_stamina)

    if (currentStamina < cost) throw new Error('Insufficient stamina')

    // 3. 执行核心业务逻辑
    let resultPayload = {}

    switch (action_type) {
      case 'procurement':
        // 采办物资：生成稀缺道具
        const item = { 
          id: `item_${Math.random().toString(36).substr(2, 9)}`, 
          name: '稀有物资', 
          type: 'consumable',
          game_id
        }
        // 写入管家背包
        await supabase.from('player_inventory').insert({
          player_id: actor_id,
          game_id,
          item_data: item
        })
        resultPayload = { item_generated: item }
        break

      case 'assignment':
        // 差使分派：目标玩家精力消耗2，获得少量银两
        await supabase.rpc('modify_player_stats', { 
          p_id: target_uid, 
          stamina_delta: -2, 
          silver_delta: 10 
        })
        break

      case 'search':
        // 搜检大观园：随机抽取5-10名玩家背包快照
        const { data: players } = await supabase
          .from('players')
          .select('id, character_name')
          .neq('id', actor_id)
          .eq('current_game_id', game_id)
          .limit(10)
        
        const snapshots = []
        for (const p of players || []) {
          const { data: inv } = await supabase.from('player_inventory').select('*').eq('player_id', p.id).limit(2)
          const { data: intel } = await supabase.from('intel_fragments').select('*').eq('owner_id', p.id).limit(2)
          snapshots.push({ player: p.character_name, inventory: inv, intel: intel })
        }
        
        resultPayload = { search_log: snapshots }
        // 写入搜检日志（可以在 action_approvals 的 params 中记录）
        break

      case 'advance':
        // 预支批条：亏空值+5%, 目标好感度+20
        await supabase.rpc('increment_deficit', { g_id: game_id, delta: 0.05 })
        // 增加好感度 (relationships 表)
        await supabase.rpc('modify_relationship', { 
          p_a: actor_id, 
          p_b: target_uid, 
          favor_delta: 20 
        })
        break

      case 'suppress_rumor':
        // 平息流言
        await supabase
          .from('rumors')
          .update({ is_suppressed: true, suppressed_by: actor_id, suppressed_at: new Date().toISOString() })
          .eq('id', params.rumor_id)
        break

      case 'block_intel':
        // 封锁消息：12小时内不可见
        const unblockAt = new Date(Date.now() + 12 * 3600 * 1000).toISOString()
        await supabase
          .from('intel_fragments')
          .update({ is_blocked: true, unblock_at: unblockAt })
          .eq('id', params.intel_id)
        break
    }

    // 4. 扣除精力并记录
    const newStamina = currentStamina - cost
    const newRefreshAt = recovered > 0 ? new Date(lastRefreshed + recovered * 2 * 3600 * 1000).toISOString() : staminaData.last_refresh_at

    await supabase
      .from('steward_stamina')
      .update({ current_stamina: newStamina, last_refresh_at: newRefreshAt })
      .eq('uid', actor_id)

    const { data: actionRecord } = await supabase
      .from('action_approvals')
      .insert({
        game_id,
        steward_uid: actor_id,
        action_type,
        target_uid,
        stamina_cost: cost,
        params: { ...params, result: resultPayload },
        status: 'executed',
        executed_at: new Date().toISOString()
      })
      .select()
      .single()

    return new Response(JSON.stringify({ success: true, action: actionRecord }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

