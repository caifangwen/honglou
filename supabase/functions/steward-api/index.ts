import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { supabase, corsHeaders } from "../_shared/supabaseClient.ts"

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const url = new URL(req.url)
  const path = url.pathname.split('/').pop()

  try {
    switch (path) {
      case 'treasury-status':
        return await handleTreasuryStatus(req)
      case 'ledger':
        return await handleLedger(req)
      case 'transfer-assets':
        return await handleTransferAssets(req)
      default:
        return new Response('Not Found', { status: 404 })
    }
  } catch (error) {
    return new Response(JSON.stringify({ error: error.message }), {
      status: 400,
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
    })
  }
})

async function handleTreasuryStatus(req: Request) {
  const { game_id } = await req.json()
  const { data, error } = await supabase
    .from('treasury')
    .select('*')
    .eq('game_id', game_id)
    .single()
  
  if (error) throw error
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function handleLedger(req: Request) {
  const { uid, game_id, type } = await req.json() // type: 'public' | 'private'
  
  let select = 'public_ledger'
  if (type === 'private') {
    // 简单校验：只有本人能看暗账
    // 实际生产应通过 auth 校验
    select = 'private_ledger, private_assets'
  }

  const { data, error } = await supabase
    .from('steward_accounts')
    .select(select)
    .eq('steward_uid', uid)
    .eq('game_id', game_id)
    .single()
  
  if (error) throw error
  return new Response(JSON.stringify(data), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}

async function handleTransferAssets(req: Request) {
  const { steward_uid, amount, game_id } = await req.json()
  
  // 末世枭雄：将私产转移到游戏外或标记为已安全转移
  const { data: account, error: aError } = await supabase
    .from('steward_accounts')
    .select('private_assets')
    .eq('steward_uid', steward_uid)
    .eq('game_id', game_id)
    .single()

  if (aError || account.private_assets < amount) throw new Error('Insufficient assets')

  await supabase
    .from('steward_accounts')
    .update({ 
      private_assets: account.private_assets - amount,
      assets_transferred: true // 需要在表中添加该字段
    })
    .eq('steward_uid', steward_uid)
  
  return new Response(JSON.stringify({ success: true }), {
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
