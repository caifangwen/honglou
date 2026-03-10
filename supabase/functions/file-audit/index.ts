
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { plaintiff_uid, defendant_uid, fragment_ids, game_id } = await req.json()

    // 1. 校验气数 (20)
    const { data: plaintiff, error: pError } = await supabase
      .from('players')
      .select('qi_shu')
      .eq('id', plaintiff_uid)
      .single()

    if (pError || !plaintiff) throw new Error('Plaintiff not found')
    if (plaintiff.qi_shu < 20) throw new Error('Insufficient Qi Shu')

    // 2. 校验碎片
    const { data: fragments, error: fError } = await supabase
      .from('intel_fragments')
      .select('*')
      .in('id', fragment_ids)
      .eq('owner_id', plaintiff_uid)

    if (fError || !fragments || fragments.length === 0) throw new Error('Evidence fragments required')

    // 3. 扣除气数并标记碎片已用
    await supabase.from('players').update({ qi_shu: plaintiff.qi_shu - 20 }).eq('id', plaintiff_uid)
    await supabase.from('intel_fragments').update({ is_used: true }).in('id', fragment_ids)

    // 4. 创建查账案件
    const deadline = new Date()
    deadline.setHours(deadline.getHours() + 24)

    const { data: auditCase, error: aError } = await supabase
      .from('audit_cases')
      .insert({
        game_id,
        plaintiff_uid,
        defendant_uid,
        evidence_fragments: fragments, // 存储碎片快照
        status: 'filed',
        deadline: deadline.toISOString()
      })
      .select()
      .single()

    if (aError) throw aError

    // 5. 广播通知 (这里简化为创建记录)
    // 实际生产可以用 Supabase Realtime 或 Webhook 推送通知。

    return new Response(JSON.stringify({ success: true, case: auditCase }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
