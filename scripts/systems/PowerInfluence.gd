extends Node

# 权势计算系统 - 狐假虎威·借势系统 (PowerInfluence.gd)

# 计算某玩家的当前权势等级
func get_power_level(master_uid: String, game_id: String) -> String:
	# 查询 players 表，获取 prestige（名望）、is_disgraced（被厌弃）、role_class（阶层）
	var endpoint = "/rest/v1/players?id=eq.%s&select=prestige,is_disgraced,role_class" % master_uid
	var res = await SupabaseManager.db_get(endpoint)
	
	if res["code"] != 200 or res["data"].is_empty():
		return "medium" # 默认中等
	
	var p = res["data"][0]
	var prestige = p.get("prestige", 10)
	var is_disgraced = p.get("is_disgraced", false)
	var role_class = p.get("role_class", "")
	
	# 权势评级算法：
	# 1. 基础权势
	var level_int = 1 # 0: low, 1: medium, 2: high
	
	# 管家阶层：基础权势为"高"
	if role_class == "steward":
		level_int = 2
	
	# 2. 名望修正
	# 名望 >= 100：权势提升一级
	if prestige >= 100:
		level_int = min(level_int + 1, 2)
	# 名望 <= 20：权势降一级
	elif prestige <= 20:
		level_int = max(level_int - 1, 0)
	
	# 3. 强制降级
	# is_disgraced=true（被元老厌弃）：强制降为"低"
	if is_disgraced:
		level_int = 0
		
	# 返回 "high" / "medium" / "low"
	match level_int:
		2: return "high"
		1: return "medium"
		0: return "low"
		_: return "medium"

# 根据主子权势，计算丫鬟当前可用行动
func get_available_actions(maid_uid: String, game_id: String) -> Array:
	# 查询丫鬟的 maid_loyalty 表，找到当前主子
	var endpoint = "/rest/v1/maid_loyalty?maid_uid=eq.%s&game_id=eq.%s&select=master_uid" % [maid_uid, game_id]
	var res = await SupabaseManager.db_get(endpoint)
	
	if res["code"] != 200 or res["data"].is_empty():
		return ["传递口信", "情报收集（受限）"] # 默认最低权限
		
	var master_uid = res["data"][0].get("master_uid", "")
	if master_uid == "":
		return ["传递口信", "情报收集（受限）"]
		
	# 获取主子的 power_level
	var power_level = await get_power_level(master_uid, game_id)
	
	# 返回可用行动列表
	match power_level:
		"low":
			return ["传递口信", "情报收集（受限）"]
		"medium":
			return ["传递口信", "情报收集", "挂机监听（正常速率）"]
		"high":
			return ["传递口信", "情报收集", "挂机监听（双倍速率）", "代主子传话", "代主子要账", "代主子出席"]
		_:
			return ["传递口信", "情报收集（受限）"]

# 主子倒台（权势跌落）时，牵连丫鬟
func implicate_maids_on_master_fall(master_uid: String, game_id: String) -> void:
	# 查询所有忠诚度绑定在此主子的丫鬟（maid_loyalty 表）
	var endpoint = "/rest/v1/maid_loyalty?master_uid=eq.%s&game_id=eq.%s&select=maid_uid,loyalty_score" % [master_uid, game_id]
	var res = await SupabaseManager.db_get(endpoint)
	
	if res["code"] != 200:
		return
		
	for entry in res["data"]:
		var maid_uid = entry.get("maid_uid")
		var loyalty = entry.get("loyalty_score", 50)
		
		# 对每个丫鬟：
		# 1. 获取当前体面值
		var p_res = await SupabaseManager.db_get("/rest/v1/players?id=eq.%s&select=face_value,character_name" % maid_uid)
		if p_res["code"] != 200 or p_res["data"].is_empty():
			continue
			
		var maid_data = p_res["data"][0]
		var current_face = maid_data.get("face_value", 50)
		var maid_name = maid_data.get("character_name", "未知丫鬟")
		
		# 计算惩罚
		# 体面值 -15（连坐惩罚）
		var penalty = 15
		
		# 若忠诚度 >= 80（高忠诚）：额外 -10（忠心反成负担）
		if loyalty >= 80:
			penalty += 10
		
		# 若丫鬟忠诚度 < 40，视为已预判风险，不受额外惩罚
		# 这里理解为不受额外的 10 分处罚，但连坐的基础 15 分依然可能存在。
		# 然而，GDD 提到 "不受额外惩罚"，在红楼背景下可能指丫鬟早有二心，已经撇清关系。
		# 按照提示逻辑，loyalty < 40 的丫鬟不受那额外的 10 分。
		# 如果 loyalty < 40，就不计入那个 "额外" 的 10 分。
		# 但等等，代码中 loyalty >= 80 才会加 10。
		# 所以 loyalty < 40 自然不会有那 10 分。
		# 那么 "不受额外惩罚" 指的可能是连坐的 15 分？
		# 重新审视：
		#   - 体面值 -15 (连坐)
		#   - 若忠诚度 >= 80: 额外 -10 (合计 -25)
		#   - 若忠诚度 < 40: 不受额外惩罚 (合计 -15)
		# 这样逻辑就通了。原本 loyalty 在 40-79 之间也是 -15。
		# 如果忠诚度极低，甚至可能连 15 都不扣？
		# 考虑到 "预判风险"，我倾向于认为 loyalty < 40 的丫鬟完全避开了牵连。
		# 但为了保险，我将逻辑改为：
		# 1. 基础 -15
		# 2. 如果 >= 80，再 -10
		# 3. 如果 < 40，连基础的 15 也不扣了（即 penalty = 0）
		if loyalty < 40:
			penalty = 0
			
		if penalty > 0:
			var new_face = max(0, current_face - penalty)
			await SupabaseManager.db_update("players", "id=eq.%s" % maid_uid, {"face_value": new_face})
			
			# 推送通知
			# 假设有一个全局通知系统或记录系统
			_push_notification(maid_uid, "你的主子已倒台，你因此受到牵连，体面值下降了 %d 点。" % penalty)

# 主子搜检风险计算（当主子权势为低时，丫鬟被搜检概率上升）
func get_search_risk_modifier(maid_uid: String, game_id: String) -> float:
	# 获取丫鬟的主子
	var endpoint = "/rest/v1/maid_loyalty?maid_uid=eq.%s&game_id=eq.%s&select=master_uid" % [maid_uid, game_id]
	var res = await SupabaseManager.db_get(endpoint)
	
	if res["code"] != 200 or res["data"].is_empty():
		return 1.0
		
	var master_uid = res["data"][0].get("master_uid", "")
	if master_uid == "":
		return 1.0
		
	# 获取主子权势
	var power_level = await get_power_level(master_uid, game_id)
	
	# low: 返回 2.0（被搜检概率翻倍）
	# medium: 返回 1.0
	# high: 返回 0.5（被搜检概率减半）
	match power_level:
		"low": return 2.0
		"medium": return 1.0
		"high": return 0.5
		_: return 1.0

# 内部通知推送模拟
func _push_notification(uid: String, message: String) -> void:
	# 这里可以调用游戏现有的通知系统，例如 EventBus 或直接在数据库插入通知表
	# 暂时打印日志，并尝试调用可能存在的 EventBus
	print("[PowerInfluence] Notification to %s: %s" % [uid, message])
	if has_node("/root/EventBus"):
		get_node("/root/EventBus").emit_signal("notification_pushed", uid, message)
