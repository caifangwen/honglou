import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { supabase, corsHeaders } from '../_shared/supabaseClient.ts'

interface PublishRumorRequest {
  game_id: string;
  target_uid: string;
  content?: string;
  intel_fragment_ids?: string[];
  source_type: 'intel_fragment' | 'freewrite';
}

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

    // 获取发布者 player 信息
    const { data: publisher, error: publisherError } = await supabase
      .from('players')
      .select('id, stamina, current_game_id')
      .eq('auth_uid', user.id)
      .single()

    if (publisherError || !publisher) {
      return new Response(JSON.stringify({ error: 'Player not found' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 404,
      })
    }

    const body: PublishRumorRequest = await req.json()
    const { game_id, target_uid, content, intel_fragment_ids, source_type } = body

    // 1. 校验精力值
    if (publisher.stamina < 5) {
      return new Response(JSON.stringify({ error: 'insufficient_stamina' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // 2. 校验目标玩家
    const { data: target, error: targetError } = await supabase
      .from('players')
      .select('id')
      .eq('id', target_uid)
      .eq('current_game_id', game_id)
      .single()

    if (targetError || !target) {
      return new Response(JSON.stringify({ error: 'target_not_found_in_game' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 404,
      })
    }

    if (publisher.id === target_uid) {
      return new Response(JSON.stringify({ error: 'cannot_target_self' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    let finalContent = content || ''
    let isGrafted = false
    let credibility = 1.0

    // 3. 处理情报来源
    if (source_type === 'intel_fragment') {
      if (!intel_fragment_ids || intel_fragment_ids.length === 0) {
        return new Response(JSON.stringify({ error: 'intel_fragments_required' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        })
      }

      // 校验碎片所有权
      const { data: fragments, error: fragmentsError } = await supabase
        .from('intel_fragments')
        .select('id, content, about_player_id')
        .in('id', intel_fragment_ids)
        .eq('owner_id', publisher.id)
        .eq('is_used', false)

      if (fragmentsError || fragments.length !== intel_fragment_ids.length) {
        return new Response(JSON.stringify({ error: 'invalid_or_used_fragments' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        })
      }

      // 设置流言内容（如果是嫁接，取第一个或合并）
      finalContent = fragments.map(f => f.content).join('；又听闻：')
      
      if (intel_fragment_ids.length === 2) {
        // 校验是否都指向同一目标
        const allTargetSame = fragments.every(f => f.about_player_id === target_uid)
        if (allTargetSame) {
          isGrafted = true
          credibility = 2.0
        } else {
          credibility = 1.5 // 碎片来源但非嫁接
        }
      } else {
        credibility = 1.5
      }

      // 标记碎片已使用
      await supabase
        .from('intel_fragments')
        .update({ is_used: true })
        .in('id', intel_fragment_ids)

    } else if (source_type === 'freewrite') {
      if (!finalContent || finalContent.trim().length === 0 || finalContent.length > 150) {
        return new Response(JSON.stringify({ error: 'invalid_content_length' }), {
          headers: { ...corsHeaders, 'Content-Type': 'application/json' },
          status: 400,
        })
      }
      credibility = 0.5
    }

    // 4. 计算时间戳
    const now = new Date()
    const stage2_at = new Date(now.getTime() + 6 * 60 * 60 * 1000)
    const stage3_at = new Date(now.getTime() + 12 * 60 * 60 * 1000)

    // 5. 插入 rumors 表
    const { data: rumor, error: rumorError } = await supabase
      .from('rumors')
      .insert({
        game_id,
        publisher_uid: publisher.id,
        target_uid: target_uid,
        content: finalContent,
        source_type,
        intel_fragment_ids,
        is_grafted,
        credibility,
        stage: 1,
        published_at: now.toISOString(),
        stage2_at: stage2_at.toISOString(),
        stage3_at: stage3_at.toISOString()
      })
      .select()
      .single()

    if (rumorError) throw rumorError

    // 6. 扣除精力
    await supabase
      .from('players')
      .update({ stamina: publisher.stamina - 5 })
      .eq('id', publisher.id)

    // 7. 插入事件日志
    await supabase
      .from('rumor_events')
      .insert({
        rumor_id: rumor.id,
        actor_uid: publisher.id,
        event_type: 'published',
        event_data: { cost: 5, source_type, is_grafted }
      })

    // 8. 发送通知给目标玩家
    await supabase
      .from('messages')
      .insert({
        game_id,
        receiver_uid: target_uid,
        message_type: 'system',
        content: '园中隐有风声，有人在背地议论你的是非，望多加小心。'
      })

    return new Response(JSON.stringify({
      success: true,
      rumor_id: rumor.id,
      stage2_at: rumor.stage2_at,
      stage3_at: rumor.stage3_at
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
