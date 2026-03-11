import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { supabase, corsHeaders } from '../_shared/supabaseClient.ts'

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const now = new Date()

    // 1. 查询所有活跃且未压制的流言
    const { data: rumors, error: rumorsError } = await supabase
      .from('rumors')
      .select('*, players:target_uid(id, display_name, reputation, face_value)')
      .lt('stage', 3)
      .eq('is_suppressed', false)

    if (rumorsError) throw rumorsError

    const updates = []

    for (const rumor of rumors) {
      const stage2At = new Date(rumor.stage2_at)
      const stage3At = new Date(rumor.stage3_at)

      // a. 阶段 2 -> 3 (板上钉钉)
      if (now >= stage3At && rumor.stage === 2) {
        const penalty = Math.floor(15 * rumor.credibility)
        const conflictInc = rumor.is_grafted ? 6 : 3

        // 更新流言状态
        await supabase
          .from('rumors')
          .update({
            stage: 3,
            penalty_applied: true
          })
          .eq('id', rumor.id)

        // 扣除目标名誉值
        await supabase
          .from('players')
          .update({ reputation: rumor.players.reputation - penalty })
          .eq('id', rumor.target_uid)

        // 增加全局内耗值
        const { data: game } = await supabase
          .from('games')
          .select('conflict_value')
          .eq('id', rumor.game_id)
          .single()
        
        if (game) {
          await supabase
            .from('games')
            .update({ conflict_value: (game.conflict_value || 0) + conflictInc })
            .eq('id', rumor.game_id)
        }

        // 记录事件
        await supabase
          .from('rumor_events')
          .insert({
            rumor_id: rumor.id,
            actor_uid: rumor.publisher_uid, // 虽然是自动触发，但责任归属于发布者
            event_type: 'penalty_applied',
            event_data: { reputation_penalty: penalty, conflict_increase: conflictInc }
          })

        // 通知目标玩家
        await supabase
          .from('messages')
          .insert({
            game_id: rumor.game_id,
            receiver_uid: rumor.target_uid,
            message_type: 'system',
            content: `木已成舟，你的名声已受到实质性损伤，名誉值-${penalty}。`
          })

        updates.push({ id: rumor.id, to_stage: 3 })
      } 
      
      // b. 阶段 1 -> 2 (人尽皆知)
      else if (now >= stage2At && rumor.stage === 1) {
        // 更新流言状态
        await supabase
          .from('rumors')
          .update({ stage: 2 })
          .eq('id', rumor.id)

        // 扣除目标体面值
        await supabase
          .from('players')
          .update({ face_value: Math.max(0, rumor.players.face_value - 5) })
          .eq('id', rumor.target_uid)

        // 记录事件
        await supabase
          .from('rumor_events')
          .insert({
            rumor_id: rumor.id,
            actor_uid: rumor.publisher_uid,
            event_type: 'stage_advanced',
            event_data: { from: 1, to: 2, face_value_penalty: 5 }
          })

        // 通知目标玩家
        await supabase
          .from('messages')
          .insert({
            game_id: rumor.game_id,
            receiver_uid: rumor.target_uid,
            message_type: 'system',
            content: '那风声如今已传得人尽皆知，你的体面已受损，速寻对策！'
          })

        // 全局通知（系统广播）
        await supabase
          .from('messages')
          .insert({
            game_id: rumor.game_id,
            message_type: 'rumor',
            content: `流言广场·新增：关于【${rumor.players.display_name}】的传言已人尽皆知。`
          })

        updates.push({ id: rumor.id, to_stage: 2 })
      }
    }

    return new Response(JSON.stringify({
      success: true,
      processed: rumors.length,
      updates
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
