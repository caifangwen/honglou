
import { supabase } from "./_shared/supabaseClient.ts"

/**
 * 贤能管家路线检测
 */
export async function checkVirtuousEnding(game_id: string, steward_uid: string) {
  const { data: treasury } = await supabase.from('treasury').select('deficit_rate').eq('game_id', game_id).single()
  const { count: auditCount } = await supabase.from('audit_cases').select('*', { count: 'exact', head: true }).eq('defendant_uid', steward_uid)
  
  // 假设有玩家满意度统计表或通过月例发放情况估算
  const avgSatisfaction = 75 // 模拟数据

  const conditions = {
    deficit_rate: (treasury?.deficit_rate || 0) <= 0.15,
    avg_satisfaction: avgSatisfaction >= 70,
    no_complaints: auditCount === 0
  }

  if (Object.values(conditions).every(v => v === true)) {
    // 发放成就
    return { achievement: "virtuous_steward", reward: "next_round_priority" }
  }
  return null
}

/**
 * 末世枭雄路线检测
 */
export async function checkSchemerEnding(game_id: string, steward_uid: string) {
  const { data: game } = await supabase.from('games').select('deficit_value').eq('id', game_id).single()
  const { data: steward } = await supabase.from('steward_accounts').select('private_assets').eq('steward_uid', steward_uid).single()

  const conditions = {
    family_collapsed: (game?.deficit_value || 0) >= 100,
    private_wealth: (steward?.private_assets || 0) >= 500,
    assets_transferred: true // 假设已完成资产转移
  }

  if (Object.values(conditions).every(v => v === true)) {
    return { achievement: "schemer_warlord", reward: "large_cash_bonus" }
  }
  return null
}
