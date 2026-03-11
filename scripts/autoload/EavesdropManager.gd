extends Node

# EavesdropManager.gd - 丫鬟挂机监听逻辑管理
# 负责会话开启、情报生成与完成校验

const COST_STAMINA = 2 # 挂机消耗2点精力

# 场景配置数据
const SCENE_CONFIGS = {
	"yi_hong_yuan": {
		"name": "怡红院后窗",
		"intel_type": ["private_action", "gift_record"],
		"base_rate": 0.6,
		"value_range": [3, 4]
	},
	"treasury_back": {
		"name": "管家后账房",
		"intel_type": ["account_leak"],
		"base_rate": 0.4,
		"value_range": [4, 5]
	},
	"bridge": {
		"name": "蜂腰桥",
		"intel_type": ["private_action"],
		"base_rate": 0.7,
		"value_range": [2, 3]
	},
	"gate": {
		"name": "荣国府大门",
		"intel_type": ["visitor_info"],
		"base_rate": 0.65,
		"value_range": [3, 4]
	},
	"elder_room": {
		"name": "贾母处",
		"intel_type": ["elder_favor"],
		"base_rate": 0.2,
		"value_range": [5, 5]
	}
}

# ─────────────────────────────────────────
# 核心方法
# ─────────────────────────────────────────

# 开始挂机
func start_eavesdrop(player_uid: String, scene: String, duration_hours: int, partner_uid: String = "") -> bool:
	# 1. 检查精力是否足够 (调用 StaminaManager 或直接查询)
	var current_stamina = await StaminaManager.get_current_stamina(player_uid)
	if current_stamina < COST_STAMINA:
		push_warning("[Eavesdrop] 精力不足")
		return false
	
	# 2. 检查该场景当前人数
	var listener_count = await get_scene_listener_count(GameState.current_game_id, scene)
	var success_rate_mod = 1.0
	if listener_count >= 5:
		success_rate_mod = 0.5 # 超过5人成功率下降50%
	
	# 3. 写入 eavesdrop_sessions 表
	var start_time = int(Time.get_unix_time_from_system())
	var end_time = start_time + (duration_hours * 3600)
	
	var session_data = {
		"player_uid": player_uid,
		"game_id": GameState.current_game_id,
		"scene_key": scene,
		"status": "active",
		"starts_at": Time.get_datetime_string_from_unix_time(start_time),
		"ends_at": Time.get_datetime_string_from_unix_time(end_time),
		"success_rate_mod": success_rate_mod,
		"partner_uid": partner_uid
	}
	
	var res = await SupabaseManager.insert_into_table("eavesdrop_sessions", session_data)
	if res["code"] != 201:
		push_error("[Eavesdrop] 开启监听失败: " + str(res["error"]))
		return false
	
	# 4. 扣除精力
	# 假设 execute_steward_action 可以扣除精力，或者手动更新表
	await SupabaseManager.db_update("steward_stamina", "uid=eq." + player_uid, {"current_stamina": current_stamina - COST_STAMINA})
	
	return true

# 生成情报碎片 (由本地定时器或后端调用)
func generate_intel_fragment(session_id: String) -> void:
	# 1. 获取会话信息
	var res = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] != 200 or res["data"].is_empty():
		return
	
	var session = res["data"][0]
	var scene_key = session["scene_key"]
	var config = SCENE_CONFIGS.get(scene_key)
	if not config: return
	
	# 2. 触发率判定
	var trigger_rate = config["base_rate"] * session["success_rate_mod"]
	if randf() > trigger_rate:
		return # 未触发
	
	# 3. 获取其他玩家最近行动 (actions 日志表，最近48小时)
	# 假设 actions 表存储玩家行为
	var now_minus_48h = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 172800)
	var action_res = await SupabaseManager.db_get("/rest/v1/actions?created_at=gt.%s&game_id=eq.%s&select=*" % [now_minus_48h, GameState.current_game_id])
	
	var intel_content = "听到了些琐碎的闲谈。" # 默认内容
	if action_res["code"] == 200 and not action_res["data"].is_empty():
		# 随机选择一个行动记录生成情报
		var action_data = action_res["data"][randi() % action_res["data"].size()]
		var intel_type = config["intel_type"][randi() % config["intel_type"].size()]
		
		# 使用 intel_templates 生成真实内容
		var IntelTemplates = load("res://scripts/data/intel_templates.gd").new()
		intel_content = IntelTemplates.format_intel(intel_type, action_data)
	
	# 4. 写入 intel_fragments 表
	var fragment_data = {
		"session_id": session_id,
		"player_uid": session["player_uid"],
		"game_id": session["game_id"],
		"content": intel_content,
		"intel_type": config["intel_type"][0], # 简化处理，取第一个
		"value_level": randi_range(config["value_range"][0], config["value_range"][1]),
		"status": "unread"
	}
	
	await SupabaseManager.insert_into_table("intel_fragments", fragment_data)
	
	# 5. 双人挂机逻辑：生成双倍碎片
	if session.get("partner_uid", "") != "":
		fragment_data["player_uid"] = session["partner_uid"]
		await SupabaseManager.insert_into_table("intel_fragments", fragment_data)

# 检查会话是否完成
func check_session_completion(session_id: String) -> void:
	var res = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] != 200 or res["data"].is_empty():
		return
	
	var session = res["data"][0]
	if session["status"] != "active":
		return
		
	var ends_at = Time.get_unix_time_from_datetime_string(session["ends_at"])
	var now = Time.get_unix_time_from_system()
	
	if ends_at <= now:
		# 更新状态为已完成
		await SupabaseManager.db_update("eavesdrop_sessions", "id=eq." + session_id, {"status": "completed"})
		
		# 统计收获情报数量
		var frag_res = await SupabaseManager.db_get("/rest/v1/intel_fragments?session_id=eq.%s&select=id" % session_id)
		var count = frag_res["data"].size() if frag_res["code"] == 200 else 0
		
		# 推送通知 (可以使用信号或 EventBus)
		var msg = "你在 [%s] 收获了 %d 条情报" % [SCENE_CONFIGS[session["scene_key"]]["name"], count]
		EventBus.emit_signal("show_notification", msg)

# 获取场景当前监听人数
func get_scene_listener_count(game_id: String, scene: String) -> int:
	var endpoint = "/rest/v1/eavesdrop_sessions?game_id=eq.%s&scene_key=eq.%s&status=eq.active&select=count" % [game_id, scene]
	# 注意：Supabase REST API count 需要特定头，或者直接查询列表取长度
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200 and res["data"] is Array:
		return res["data"].size()
	return 0
