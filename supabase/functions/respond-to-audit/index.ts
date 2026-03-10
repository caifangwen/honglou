
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { action, case_id, steward_uid, fragment_id, game_id } = await req.json()

    // 1. 获取管家私产
    const { data: steward, error: sError } = await supabase
      .from('steward_accounts')
      .select('private_assets')
      .eq('steward_uid', steward_uid)
      .eq('game_id', game_id)
      .single()

    if (sError || !steward) throw new Error('Steward data not found')

    let cost = 0
    let updateData = {}

    switch (action) {
      case 'destroy_evidence':
        cost = 30
        if (steward.private_assets < cost) throw new Error('Insufficient private assets')
        // 标记碎片为"待删除"，需元老批准。这里简化为更新案件数据。
        updateData = { pending_evidence_removal: fragment_id }
        break

      case 'bribe_witness':
        cost = 50
        if (steward.private_assets < cost) throw new Error('Insufficient private assets')
        // 降低举报者可信度 (假设 audit_cases 有 plaintiff_credibility 字段)
        updateData = { plaintiff_credibility: 0 } 
        break

      case 'counteraccuse':
        cost = 0 // 使用情报碎片，不扣银子
        // 检查碎片
        const { data: fragments } = await supabase.from('intel_fragments').select('*').eq('id', fragment_id).single()
        if (!fragments) throw new Error('Evidence not found')
        // 这里简化为标记案件状态
        updateData = { counter_accused: true, new_target: fragments.about_player_id }
        break
    }

    // 2. 扣款并更新案件
    if (cost > 0) {
      await supabase.from('steward_accounts').update({ private_assets: steward.private_assets - cost }).eq('steward_uid', steward_uid)
    }

    await supabase.from('audit_cases').update(updateData).eq('id', case_id)

    return new Response(JSON.stringify({ success: true }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
