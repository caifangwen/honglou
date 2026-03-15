extends Node

# EavesdropManager.gd - 丫鬟挂机监听逻辑管理
# 负责会话开启、情报生成与完成校验

signal session_started(session_id: String)
signal session_completed(session_id: String, intel_count: int)
signal intel_received(content: String, value_level: int)

const COST_STAMINA = 2 # 挂机消耗 2 点精力
const DUO_BONUS_RATE = 0.2 # 双人挂机奖励：+20% 触发率
const DUO_EXTRA_FRAGMENT = 1 # 双人挂机额外碎片数

# 场景配置数据
const SCENE_CONFIGS = {
	"yi_hong_yuan": {
		"name": "怡红院后窗",
		"intel_type": ["private_action", "gift_record"],
		"base_rate": 0.6,
		"value_range": [3, 4],
		"description": "可监听怡红院内丫鬟们的私密对话和私下馈赠"
	},
	"treasury_back": {
		"name": "管家后账房",
		"intel_type": ["account_leak"],
		"base_rate": 0.4,
		"value_range": [4, 5],
		"description": "可探听管家账目漏洞，收益高但风险大"
	},
	"bridge": {
		"name": "蜂腰桥",
		"intel_type": ["private_action"],
		"base_rate": 0.7,
		"value_range": [2, 3],
		"description": "人来人往之地，容易听到闲言碎语"
	},
	"gate": {
		"name": "荣国府大门",
		"intel_type": ["visitor_info"],
		"base_rate": 0.65,
		"value_range": [3, 4],
		"description": "可获取来访客人信息"
	},
	"elder_room": {
		"name": "贾母处",
		"intel_type": ["elder_favor"],
		"base_rate": 0.2,
		"value_range": [5, 5],
		"description": "可探听贾母对各位丫鬟的评价，极为稀有"
	}
}

# 活跃会话定时器
var _session_timers: Dictionary = {} # session_id -> Timer
var _completion_check_timer: Timer

# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready():
	SupabaseManager.realtime_update.connect(_on_realtime_update)
	SupabaseManager.subscribe_to_table("intel_fragments")
	
	# 创建完成检查定时器（每 30 秒检查一次）
	_completion_check_timer = Timer.new()
	_completion_check_timer.wait_time = 30.0
	_completion_check_timer.timeout.connect(_check_all_sessions_completion)
	_completion_check_timer.autostart = true
	add_child(_completion_check_timer)
	
	# 恢复活跃会话的定时器
	await _restore_active_sessions()

# ─────────────────────────────────────────
# 实时通知
# ─────────────────────────────────────────

func _on_realtime_update(table_name: String, data: Dictionary):
	if table_name == "intel_fragments" and data.get("eventType") == "INSERT":
		var record = data.get("new", {})
		if record.get("player_uid", "") == PlayerState.uid:
			var content = record.get("content", "听到了些闲谈。")
			var value_level = record.get("value_level", 1)
			var msg = "【新情报】" + content
			if EventBus.has_signal("show_notification"):
				EventBus.emit_signal("show_notification", msg)
			intel_received.emit(content, value_level)
			print("[Eavesdrop] Received realtime intel: ", content)

# ─────────────────────────────────────────
# 核心方法 - 开始挂机
# ─────────────────────────────────────────

func start_eavesdrop(player_uid: String, scene: String, duration_hours: int, partner_uid: String = "") -> bool:
	# 1. 检查精力是否足够
	var current_stamina = await StaminaManager.get_current_stamina(player_uid)
	if current_stamina < COST_STAMINA:
		push_warning("[Eavesdrop] 精力不足")
		return false

	# 2. 检查该场景当前人数
	var listener_count = await get_scene_listener_count(GameState.current_game_id, scene)
	var success_rate_mod = 1.0
	if listener_count >= 5:
		success_rate_mod = 0.5 # 超过 5 人成功率下降 50%
	elif listener_count >= 3:
		success_rate_mod = 0.8 # 3-5 人下降 20%

	# 3. 计算结束时间
	var start_time = int(Time.get_unix_time_from_system())
	var end_time = start_time + (duration_hours * 3600)

	# 4. 构建会话数据
	var session_data = {
		"player_uid": player_uid,
		"game_id": GameState.current_game_id,
		"scene": scene,
		"scene_key": scene,
		"status": "active",
		"starts_at": Time.get_datetime_string_from_unix_time(start_time),
		"ends_at": Time.get_datetime_string_from_unix_time(end_time),
		"success_rate_mod": success_rate_mod,
		"partner_uid": partner_uid if partner_uid != "" else null,
		"is_duo": partner_uid != "",
		"result_count": 0
	}

	# 5. 写入数据库
	var res = await SupabaseManager.insert_into_table("eavesdrop_sessions", session_data)
	if res["code"] != 201:
		push_error("[Eavesdrop] 开启监听失败：" + str(res["error"]))
		return false

	var session_id = res["data"][0]["id"]
	
	# 6. 扣除精力（使用 PlayerState 的 consume_stamina 方法）
	if not PlayerState.consume_stamina(COST_STAMINA):
		push_warning("[Eavesdrop] 本地精力扣除失败")
		# 回滚会话
		await SupabaseManager.db_update("eavesdrop_sessions", "id=eq." + session_id, {"status": "cancelled"})
		return false
	
	# 7. 启动定时器
	_start_session_timer(session_id, end_time)
	
	# 8. 触发信号
	session_started.emit(session_id)

	return true

# ─────────────────────────────────────────
# 核心方法 - 会话管理
# ─────────────────────────────────────────

func _start_session_timer(session_id: String, end_time: int):
	var timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = max(1.0, float(end_time - Time.get_unix_time_from_system()))
	timer.timeout.connect(func(): _on_session_timer_timeout(session_id))
	add_child(timer)
	timer.start()
	_session_timers[session_id] = timer

func _on_session_timer_timeout(session_id: String):
	await check_session_completion(session_id)

func _restore_active_sessions():
	var res = await SupabaseManager.db_get(
		"/rest/v1/eavesdrop_sessions?player_uid=eq.%s&status=eq.active&select=*" % PlayerState.uid
	)
	if res["code"] == 200:
		for session in res["data"]:
			var end_time = Time.get_unix_time_from_datetime_string(session["ends_at"])
			if end_time > Time.get_unix_time_from_system():
				_start_session_timer(session["id"], end_time)

func _check_all_sessions_completion():
	var res = await SupabaseManager.db_get(
		"/rest/v1/eavesdrop_sessions?player_uid=eq.%s&status=eq.active&select=*" % PlayerState.uid
	)
	if res["code"] == 200:
		for session in res["data"]:
			await check_session_completion(session["id"])

# ─────────────────────────────────────────
# 核心方法 - 情报生成
# ─────────────────────────────────────────

func generate_intel_fragment(session_id: String, force: bool = false) -> void:
	# 1. 获取会话信息
	var res = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] != 200 or res["data"].is_empty():
		return

	var session = res["data"][0]
	
	# 检查玩家是否被拦截
	var intercept_res = await SupabaseManager.db_get(
		"/rest/v1/intel_intercepts?target_uid=eq.%s&status=eq.active&ends_at=gt.now&select=id" % session["player_uid"]
	)
	if intercept_res["code"] == 200 and not intercept_res["data"].is_empty():
		print("[Eavesdrop] 玩家 %s 被拦截，无法生成情报" % session["player_uid"])
		return
	
	var scene_key = session["scene_key"]
	var config = SCENE_CONFIGS.get(scene_key)
	if not config:
		return

	# 2. 触发率判定（双人挂机有奖励）
	var trigger_rate = config["base_rate"] * session["success_rate_mod"]
	if session.get("is_duo", false):
		trigger_rate += DUO_BONUS_RATE
	
	if not force and randf() > trigger_rate:
		return # 未触发

	# 3. 获取其他玩家最近行动
	var now_minus_48h = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 172800)
	var action_res = await SupabaseManager.db_get(
		"/rest/v1/actions?created_at=gt.%s&game_id=eq.%s&select=*" % [now_minus_48h, GameState.current_game_id]
	)

	var intel_content = "听到了些琐碎的闲谈，没什么特别的。"
	var intel_type = config["intel_type"][randi() % config["intel_type"].size()]
	
	if action_res["code"] == 200 and not action_res["data"].is_empty():
		var action_data = action_res["data"][randi() % action_res["data"].size()]
		var IntelTemplates = load("res://scripts/data/intel_templates.gd").new()
		intel_content = IntelTemplates.format_intel(intel_type, action_data)
	else:
		# 无行动记录时使用备用模板
		intel_content = _generate_fallback_intel(intel_type, scene_key)

	# 4. 写入 intel_fragments 表
	var fragment_data = {
		"session_id": session_id,
		"player_uid": session["player_uid"],
		"game_id": session["game_id"],
		"content": intel_content,
		"intel_type": intel_type,
		"scene": scene_key,
		"value_level": randi_range(config["value_range"][0], config["value_range"][1]),
		"status": "unread",
		"is_used": false,
		"is_sold": false
	}

	var frag_res = await SupabaseManager.insert_into_table("intel_fragments", fragment_data)
	
	# 5. 更新会话结果计数
	var new_count = (session.get("result_count", 0) + 1)
	await SupabaseManager.db_update("eavesdrop_sessions", "id=eq." + session_id, {"result_count": new_count})

	# 6. 双人挂机逻辑：生成双倍碎片
	if session.get("is_duo", false) and session.get("partner_uid", "") != "":
		fragment_data["player_uid"] = session["partner_uid"]
		fragment_data["value_level"] = mini(fragment_data["value_level"] + DUO_EXTRA_FRAGMENT, 5)
		await SupabaseManager.insert_into_table("intel_fragments", fragment_data)

# 备用情报模板（当 actions 表为空时）
func _generate_fallback_intel(intel_type: String, scene_key: String) -> String:
	var fallbacks = {
		"account_leak": [
			"听说管家最近账目有些问题，但具体说不清楚。",
			"有人在议论账房里的数字对不上。"
		],
		"gift_record": [
			"瞧见有人偷偷递了个包裹进去，不知是什么物件。",
			"听说哪位姑娘私下收了份厚礼。"
		],
		"private_action": [
			"瞧见个人影匆匆往那边去了，没看清是谁。",
			"听见两人在角落里低语，听不真切。"
		],
		"visitor_info": [
			"门外来了个生面孔，放下东西就走了。",
			"听说有远客来访，带了稀罕物件。"
		],
		"elder_favor": [
			"老太太今儿个心情好，夸了两个人。",
			"听说老太太对某个丫鬟颇为满意。"
		]
	}
	
	var type_fallbacks = fallbacks.get(intel_type, ["听到了些闲谈。"])
	return type_fallbacks[randi() % type_fallbacks.size()]

# ─────────────────────────────────────────
# 核心方法 - 会话完成
# ─────────────────────────────────────────

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
		
		# 清理定时器
		if _session_timers.has(session_id):
			_session_timers[session_id].queue_free()
			_session_timers.erase(session_id)

		# 统计收获情报数量
		var frag_res = await SupabaseManager.db_get(
			"/rest/v1/intel_fragments?session_id=eq.%s&select=id" % session_id
		)
		var count = frag_res["data"].size() if frag_res["code"] == 200 else 0

		# 推送通知
		var scene_name = SCENE_CONFIGS.get(session["scene_key"], {}).get("name", session["scene_key"])
		var msg = "【挂机完成】你在 [%s] 收获了 %d 条情报" % [scene_name, count]
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", msg)
		
		session_completed.emit(session_id, count)

# ─────────────────────────────────────────
# 公共方法
# ─────────────────────────────────────────

func get_scene_listener_count(game_id: String, scene: String) -> int:
	var endpoint = "/rest/v1/eavesdrop_sessions?game_id=eq.%s&scene_key=eq.%s&status=eq.active&select=id" % [game_id, scene]
	var res = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200 and res["data"] is Array:
		return res["data"].size()
	return 0

func get_active_sessions() -> Array:
	var res = await SupabaseManager.db_get(
		"/rest/v1/eavesdrop_sessions?player_uid=eq.%s&status=eq.active&select=*" % PlayerState.uid
	)
	if res["code"] == 200:
		return res["data"]
	return []

func get_session_time_remaining(session_id: String) -> int:
	var session = await _get_session(session_id)
	if session.is_empty():
		return 0
	var ends_at = Time.get_unix_time_from_datetime_string(session["ends_at"])
	var remaining = ends_at - Time.get_unix_time_from_system()
	return max(0, remaining)

func _get_session(session_id: String) -> Dictionary:
	var res = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] == 200 and not res["data"].is_empty():
		return res["data"][0]
	return {}

func cancel_session(session_id: String) -> bool:
	var session = await _get_session(session_id)
	if session.is_empty():
		return false
	
	# 只能取消未完成的会话
	if session["status"] != "active":
		return false
	
	# 更新状态
	var res = await SupabaseManager.db_update(
		"eavesdrop_sessions", 
		"id=eq." + session_id, 
		{"status": "cancelled"}
	)
	
	# 清理定时器
	if _session_timers.has(session_id):
		_session_timers[session_id].queue_free()
		_session_timers.erase(session_id)
	
	return res["code"] == 200
