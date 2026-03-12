
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { steward_uid, game_id, distributions } = await req.json()

    if (!distributions || !Array.isArray(distributions)) {
      throw new Error('Invalid distributions data')
    }

    // 1. 获取银库数据
    const { data: treasury, error: tError } = await supabase
      .from('treasury')
      .select('*')
      .eq('game_id', game_id)
      .single()

    if (tError || !treasury) throw new Error('Treasury not found')

    const results = []
    let totalActualAmount = 0
    let totalWithheldAmount = 0

    // 2. 预先获取管家账户数据以更新 ledger
    const { data: stewardAcc, error: saError } = await supabase
      .from('steward_accounts')
      .select('public_ledger, private_ledger, private_assets')
      .eq('steward_uid', steward_uid)
      .eq('game_id', game_id)
      .single()

    if (saError) throw new Error('Steward account not found')

    let currentPublicLedger = [...(stewardAcc.public_ledger || [])]
    let currentPrivateLedger = [...(stewardAcc.private_ledger || [])]
    let currentPrivateAssets = stewardAcc.private_assets || 0

    // 3. 循环处理每一个发放
    for (const dist of distributions) {
      const { recipient_uid, recipient_name, actual_amount, standard_amount } = dist
      const withheld = standard_amount - actual_amount
      
      totalActualAmount += actual_amount
      totalWithheldAmount += withheld

      // a. 更新玩家银两 (使用 RPC)
      await supabase.rpc('modify_player_stats', {
        p_id: recipient_uid,
        private_silver_delta: actual_amount
      })

      // b. 准备账本条目
      const timestamp = new Date().toISOString()
      
      // 明账
      currentPublicLedger.push({
        type: 'allowance',
        recipient_uid,
        recipient_name,
        amount: actual_amount,
        timestamp
      })

      // 暗账 (如果有克扣)
      if (withheld > 0) {
        currentPrivateLedger.push({
          type: 'embezzlement',
          recipient_uid,
          recipient_name,
          standard: standard_amount,
          actual: actual_amount,
          withheld: withheld,
          timestamp
        })
        currentPrivateAssets += withheld
      }

      // c. 插入发放记录
      await supabase.from('allowance_records').insert({
        game_id,
        issued_by: steward_uid,
        player_id: recipient_uid,
        amount_public: standard_amount,
        amount_actual: actual_amount,
        withheld_amount: withheld,
        issued_at: timestamp
      })

      // d. 插入流水记录 (ledger_entries)
      await supabase.from('ledger_entries').insert({
        game_id,
        treasury_id: treasury.id,
        ledger_type: 'public',
        entry_type: 'allocation',
        amount: actual_amount,
        actor_id: steward_uid,
        target_id: recipient_uid,
        note: `发放月例: ${actual_amount} 两`,
        created_at: timestamp
      })

      if (withheld > 0) {
        await supabase.from('ledger_entries').insert({
          game_id,
          treasury_id: treasury.id,
          ledger_type: 'private',
          entry_type: 'allocation',
          amount: withheld,
          actor_id: steward_uid,
          target_id: recipient_uid,
          note: `克扣月例: ${withheld} 两`,
          created_at: timestamp
        })
      }
    }

    // 4. 批量更新银库
    if (treasury.total_silver < totalActualAmount) {
        throw new Error('Insufficient funds in treasury for total distribution')
    }
    await supabase.rpc('decrement_treasury', { g_id: game_id, amount: totalActualAmount })

    // 5. 更新管家账户 (一次性更新)
    await supabase
      .from('steward_accounts')
      .update({ 
        public_ledger: currentPublicLedger,
        private_ledger: currentPrivateLedger,
        private_assets: currentPrivateAssets
      })
      .eq('steward_uid', steward_uid)
      .eq('game_id', game_id)

    // 6. (可选) 风险检测/碎片生成逻辑可以放在这里
    // 简化处理，如果是批量发放，且总克扣大于一定比例，生成碎片
    if (totalWithheldAmount > 0) {
       // 这里可以添加逻辑，比如检测克扣人数
       const withheldCount = distributions.filter(d => d.standard_amount > d.actual_amount).length
       if (withheldCount >= 3) {
          await supabase.from('intel_fragments').insert({
            game_id,
            intel_type: 'account_leak',
            content: `本月发放月银，竟然有 ${withheldCount} 位下人私下议论数额不对。`,
            source_uid: steward_uid,
            owner_uid: steward_uid, // 待随机分配
            scene: 'treasury_back'
          })
       }
    }

    return new Response(JSON.stringify({ success: true, total_distributed: totalActualAmount }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })

  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})
