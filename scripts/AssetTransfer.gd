extends Node

# 资产转移逻辑（在抄家事件触发前调用）
func attempt_asset_transfer(player_uid: String, game_id: String, amount: int) -> bool:
	# 1. 检查：家族内耗值是否 < 80%（抄家前操作窗口）
	var game_res = await SupabaseManager.db_get("/rest/v1/games?id=eq." + game_id + "&select=conflict_value")
	if game_res["code"] != 200 or game_res["data"].is_empty():
		push_error("无法获取游戏状态")
		return false
	
	var conflict_value = game_res["data"][0].get("conflict_value", 0.0)
	
	# 若内耗值 >= 80%：拒绝转移，提示"为时已晚，抄家已开始"
	if conflict_value >= 80.0:
		EventBus.notify_player.emit("为时已晚，抄家已开始，资产已被封锁！")
		return false
	
	# 2. 检查玩家余额
	var player_res = await SupabaseManager.db_get("/rest/v1/players?id=eq." + player_uid + "&select=silver")
	if player_res["code"] != 200 or player_res["data"].is_empty():
		return false
	
	var current_silver = player_res["data"][0].get("silver", 0)
	if current_silver < amount:
		EventBus.notify_player.emit("余额不足，无法转移资产")
		return false
	
	# 3. 若满足内耗值 < 80%：
	# - 从玩家账户扣除 amount
	var update_res = await SupabaseManager.db_update("players", "id=eq." + player_uid, {"silver": current_silver - amount})
	if update_res["code"] != 200:
		return false
		
	# - 写入 asset_transfers 表（transfer_uid, amount, transferred_at）
	# 注意：prompt 中写的是 transfer_uid，通常对应 player_uid
	var transfer_data = {
		"game_id": game_id,
		"player_uid": player_uid,
		"amount": amount,
		"transferred_at": Time.get_datetime_string_from_system(true)
	}
	await SupabaseManager.db_insert("asset_transfers", transfer_data)
	
	# - 转移的资产在清算时不受抄家影响，且折算双倍 (由 MaidProgressionChecker 处理成就和加成)
	# - 更新 has_transferred_assets_before_raid = true (这个标记可以通过查询 asset_transfers 表是否存在记录来判断)
	
	EventBus.notify_player.emit("资产转移成功！已安全转移 %d 两白银。" % amount)
	
	# 转移后检查一次进度
	if MaidProgressionChecker:
		MaidProgressionChecker.check_all_paths(player_uid, game_id)
		
	return true
