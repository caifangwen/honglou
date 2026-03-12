
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { steward_uid, recipient_uid, actual_amount, standard_amount, game_id } = await req.json()

    // 1. 获取银库并校验
    const { data: treasury, error: tError } = await supabase
      .from('treasury')
      .select('*')
      .eq('game_id', game_id)
      .single()

    if (tError || !treasury) throw new Error('Treasury not found')
    if (treasury.total_silver < actual_amount) throw new Error('Insufficient funds in treasury')

    // 2. 计算克扣
    const withheld = standard_amount - actual_amount
    const ratio = withheld / standard_amount

    // 3. 执行原子更新 (模拟事务)
    // 扣除银库
    await supabase.rpc('decrement_treasury', { g_id: game_id, amount: actual_amount })

    // 更新管家私产与账本
    if (withheld > 0) {
      const privateEntry = {
        type: 'embezzlement',
        recipient_uid,
        standard: standard_amount,
        actual: actual_amount,
        withheld: withheld,
        timestamp: new Date().toISOString()
      }
      
      const { data: account } = await supabase
        .from('steward_accounts')
        .select('private_assets, private_ledger')
        .eq('steward_uid', steward_uid)
        .eq('game_id', game_id)
        .single()

      await supabase
        .from('steward_accounts')
        .update({ 
          private_assets: (account?.private_assets || 0) + withheld,
          private_ledger: [...(account?.private_ledger || []), privateEntry]
        })
        .eq('steward_uid', steward_uid)
        .eq('game_id', game_id)
    }

    // 写入明账
    const { data: stewardAcc } = await supabase
      .from('steward_accounts')
      .select('public_ledger')
      .eq('steward_uid', steward_uid)
      .eq('game_id', game_id)
      .single()

    const publicEntry = {
      type: 'allowance',
      recipient_uid,
      amount: actual_amount,
      timestamp: new Date().toISOString()
    }
    
    await supabase
      .from('steward_accounts')
      .update({ public_ledger: [...(stewardAcc?.public_ledger || []), publicEntry] })
      .eq('steward_uid', steward_uid)
      .eq('game_id', game_id)

    // 4. 写入发放记录
    await supabase.from('allowance_records').insert({
      game_id,
      issued_by: steward_uid,
      player_id: recipient_uid,
      amount_public: standard_amount,
      amount_actual: actual_amount,
      withheld_amount: withheld,
      issued_at: new Date().toISOString()
    })

    // 5. 触发告状风险检测 (本旬内克扣人数 >= 3)
    const { count } = await supabase
      .from('allowance_records')
      .select('*', { count: 'exact', head: true })
      .eq('issued_by', steward_uid)
      .eq('game_id', game_id)
      .gt('withheld_amount', 0)
      .gte('created_at', new Date(Date.now() - 10 * 24 * 60 * 60 * 1000).toISOString())

    if (count !== null && count >= 3) {
      // 写入风险告警，这里简化为直接在 intel_fragments 中生成一条随机碎片
      await supabase.from('intel_fragments').insert({
        game_id,
        intel_type: 'account_leak',
        content: `有人偶然发现账房的月例支出似乎与各房领到的数额对不上。`,
        source_uid: steward_uid,
        owner_uid: steward_uid, // 待系统随机分配，这里先写管家作为源头
        scene: 'treasury_back'
      })
    }

    // 6. 碎片生成逻辑 (克扣比例)
    let fragmentChance = 0
    let targetServantCount = 0

    if (ratio >= 0.25) {
      fragmentChance = 0.8
      targetServantCount = -1 // 所有丫鬟
    } else if (ratio >= 0.10) {
      fragmentChance = 0.4
      targetServantCount = 2
    } else if (ratio > 0) {
      fragmentChance = 0.15
      targetServantCount = 1
    }

    if (Math.random() < fragmentChance) {
      // 获取服侍该玩家的丫鬟
      const { data: servants } = await supabase
        .from('players')
        .select('id')
        .eq('role_class', 'servant')
        .eq('current_game_id', game_id)
        .limit(targetServantCount === -1 ? 100 : targetServantCount)

      if (servants && servants.length > 0) {
        const fragments = servants.map(s => ({
          game_id,
          owner_uid: s.id,
          intel_type: 'account_leak',
          content: `听闻被克扣了 ${withheld} 两月例。`,
          source_uid: steward_uid,
          scene: 'bridge'
        }))
        await supabase.from('intel_fragments').insert(fragments)
      }
    }

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

