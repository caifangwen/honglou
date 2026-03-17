extends Node

# 每次玩家行动后调用，检查三条路径进度
func check_all_paths(player_uid: String, game_id: String) -> void:
	await _check_head_maid(player_uid, game_id)
	await _check_concubine_path(player_uid, game_id)
	await _check_redemption_path(player_uid, game_id)

# 路径一：首席大丫鬟检测
func _check_head_maid(player_uid: String, game_id: String) -> void:
	# 1. 查询 maid_loyalty 表，获取对当前主子的 loyalty_score
	var loyalty_res = await SupabaseManager.db_get("/rest/v1/maid_loyalty?maid_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=loyalty_score")
	if loyalty_res["code"] != 200 or loyalty_res["data"].is_empty():
		return
	var loyalty_score = loyalty_res["data"][0].get("loyalty_score", 0)

	# 2. 查询 events 表，统计玩家参与处理突发事件的次数
	# 假设 events 表中 payload 包含参与者列表或有专门的参与记录表
	# 这里简化处理：查询以该玩家为 actor_id 的成功处理事件次数
	var event_res = await SupabaseManager.db_get("/rest/v1/actions?actor_id=eq." + player_uid + "&game_id=eq." + game_id + "&status=eq.resolved&select=count")
	var event_count = 0
	if event_res["code"] == 200 and event_res["data"] is Array:
		# Supabase count query returns an array with a count object or just the number depending on headers
		# Since we use select=count, it might be in a specific format
		event_count = event_res["data"].size() # 临时方案：如果 select=count 不好用，就查列表算 size

	# 检查是否已经获得成就
	var achievement_res = await SupabaseManager.db_get("/rest/v1/achievements?player_uid=eq." + player_uid + "&type=eq.head_maid&select=id")
	var already_unlocked = achievement_res["code"] == 200 and !achievement_res["data"].is_empty()

	# 条件：loyalty_score >= 90 AND event_count >= 5
	if loyalty_score >= 90 and event_count >= 5 and not already_unlocked:
		# 写入 achievements 表
		await SupabaseManager.db_insert("achievements", {
			"player_uid": player_uid,
			"game_id": game_id,
			"type": "head_maid"
		})
		
		# 为玩家解锁"副主子权限"（更新 players 表 permissions 字段）
		# 假设 permissions 是个 JSONB 数组
		var player_res = await SupabaseManager.db_get("/rest/v1/players?id=eq." + player_uid + "&select=permissions")
		var permissions = []
		if player_res["code"] == 200 and !player_res["data"].is_empty():
			permissions = player_res["data"][0].get("permissions", [])
		
		if not "vice_master" in permissions:
			permissions.append("vice_master")
			await SupabaseManager.db_update("players", "id=eq." + player_uid, {"permissions": permissions})

		# 推送通知
		EventBus.notify_player.emit("恭喜！你已成为首席大丫鬟，现可影响主子的重大决策")

# 路径二：收房/姨娘检测 
func _check_concubine_path(player_uid: String, game_id: String) -> void:
	# 查询与主子的互动次数（messages sent/received + 共同参与事件）
	var sent_res = await SupabaseManager.db_get("/rest/v1/messages?sender_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=id")
	var recv_res = await SupabaseManager.db_get("/rest/v1/messages?receiver_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=id")
	
	var interaction_count = 0
	if sent_res["code"] == 200: interaction_count += sent_res["data"].size()
	if recv_res["code"] == 200: interaction_count += recv_res["data"].size()
	
	# 检查是否已触发主子专属剧情（查询 special_events 表）
	var story_res = await SupabaseManager.db_get("/rest/v1/special_events?player_uid=eq." + player_uid + "&game_id=eq." + game_id + "&event_name=eq.master_special_story&select=id")
	var has_triggered_special_story = story_res["code"] == 200 and !story_res["data"].is_empty()

	# 检查是否已经获得成就
	var achievement_res = await SupabaseManager.db_get("/rest/v1/achievements?player_uid=eq." + player_uid + "&type=eq.concubine&select=id")
	var already_unlocked = achievement_res["code"] == 200 and !achievement_res["data"].is_empty()

	# 条件：interaction_count >= 20 AND has_triggered_special_story = true
	if interaction_count >= 20 and has_triggered_special_story and not already_unlocked:
		# 写入 achievements 表
		await SupabaseManager.db_insert("achievements", {
			"player_uid": player_uid,
			"game_id": game_id,
			"type": "concubine"
		})
		
		# 在 next_game_preferences 表写入："下一局以主子阶层开局"
		await SupabaseManager.db_insert("next_game_preferences", {
			"player_uid": player_uid,
			"preference": "start_as_master"
		})
		
		# 触发主子专属剧情结局叙事文本显示
		EventBus.trigger_ending_narrative.emit("concubine_ending")

# 路径三：赎身出府检测
func _check_redemption_path(player_uid: String, game_id: String) -> void:
	# 查询玩家当前银两总量
	var player_res = await SupabaseManager.db_get("/rest/v1/players?id=eq." + player_uid + "&select=silver,display_name")
	if player_res["code"] != 200 or player_res["data"].is_empty():
		return
	var silver = player_res["data"][0].get("silver", 0)
	var player_name = player_res["data"][0].get("display_name", "玩家")

	# 查询是否在抄家前成功执行了"转移资产"操作
	var transfer_res = await SupabaseManager.db_get("/rest/v1/asset_transfers?player_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=id")
	var has_transferred_assets_before_raid = transfer_res["code"] == 200 and !transfer_res["data"].is_empty()

	# 检查是否已经获得成就
	var achievement_res = await SupabaseManager.db_get("/rest/v1/achievements?player_uid=eq." + player_uid + "&type=eq.redemption&select=id")
	var already_unlocked = achievement_res["code"] == 200 and !achievement_res["data"].is_empty()

	# 条件：silver >= 300 AND has_transferred_assets_before_raid = true
	if silver >= 300 and has_transferred_assets_before_raid and not already_unlocked:
		# 写入 achievements 表
		await SupabaseManager.db_insert("achievements", {
			"player_uid": player_uid,
			"game_id": game_id,
			"type": "redemption"
		})
		
		# 在清算时，个人财产折算双倍（写入 settlement_bonus 表）
		await SupabaseManager.db_insert("settlement_bonus", {
			"player_uid": player_uid,
			"game_id": game_id,
			"bonus_multiplier": 2.0
		})
		
		# 推送全局通知
		EventBus.broadcast_message.emit("[%s]已赎身出府，全身而退！" % player_name)

# 获取玩家当前路径进度
func get_path_progress(player_uid: String, game_id: String) -> Dictionary:
	var progress = {
		"head_maid": {
			"loyalty": 0,
			"events_handled": 0,
			"unlocked": false
		},
		"concubine": {
			"interactions": 0,
			"special_story_triggered": false,
			"unlocked": false
		},
		"redemption": {
			"silver": 0,
			"assets_transferred": false,
			"unlocked": false
		}
	}
	
	# 获取各项数据
	var loyalty_res = await SupabaseManager.db_get("/rest/v1/maid_loyalty?maid_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=loyalty_score")
	if loyalty_res["code"] == 200 and !loyalty_res["data"].is_empty():
		progress.head_maid.loyalty = loyalty_res["data"][0].get("loyalty_score", 0)
	
	var actions_res = await SupabaseManager.db_get("/rest/v1/actions?actor_id=eq." + player_uid + "&game_id=eq." + game_id + "&status=eq.resolved&select=id")
	if actions_res["code"] == 200:
		progress.head_maid.events_handled = actions_res["data"].size()
	
	var sent_res = await SupabaseManager.db_get("/rest/v1/messages?sender_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=id")
	var recv_res = await SupabaseManager.db_get("/rest/v1/messages?receiver_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=id")
	if sent_res["code"] == 200: progress.concubine.interactions += sent_res["data"].size()
	if recv_res["code"] == 200: progress.concubine.interactions += recv_res["data"].size()
	
	var story_res = await SupabaseManager.db_get("/rest/v1/special_events?player_uid=eq." + player_uid + "&game_id=eq." + game_id + "&event_name=eq.master_special_story&select=id")
	progress.concubine.special_story_triggered = (story_res["code"] == 200 and !story_res["data"].is_empty())
	
	var player_res = await SupabaseManager.db_get("/rest/v1/players?id=eq." + player_uid + "&select=silver")
	if player_res["code"] == 200 and !player_res["data"].is_empty():
		progress.redemption.silver = player_res["data"][0].get("silver", 0)
	
	var transfer_res = await SupabaseManager.db_get("/rest/v1/asset_transfers?player_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=id")
	progress.redemption.assets_transferred = (transfer_res["code"] == 200 and !transfer_res["data"].is_empty())
	
	# 检查解锁状态
	var ach_res = await SupabaseManager.db_get("/rest/v1/achievements?player_uid=eq." + player_uid + "&game_id=eq." + game_id + "&select=type")
	if ach_res["code"] == 200:
		for ach in ach_res["data"]:
			if ach.type == "head_maid": progress.head_maid.unlocked = true
			elif ach.type == "concubine": progress.concubine.unlocked = true
			elif ach.type == "redemption": progress.redemption.unlocked = true
			
	return progress
