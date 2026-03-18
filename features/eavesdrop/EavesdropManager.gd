extends Node

# EavesdropManager.gd - 丫鬟挂机监听逻辑管理
# 负责会话开启、情报生成与完成校验

const IntelTemplates = preload("res://features/eavesdrop/IntelTemplates.gd")

signal session_started(session_id: String)
signal session_completed(session_id: String, intel_count: int)
signal intel_received(content: String, value_level: int)

# 精力消耗（统一引用 GameConfig 常量）
const COST_STAMINA: int = GameConfig.COST_SEARCH_GARDEN
const DUO_BONUS_RATE: float = 0.2
const DUO_EXTRA_FRAGMENT: int = 1

# 场景配置数据 (Dictionary: String -> Dictionary)
const SCENE_CONFIGS: Dictionary = {
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
	},
	"remote_rockery": {
		"name": "偏僻假山",
		"intel_type": ["dui_shi", "private_action"],
		"base_rate": 0.5,
		"value_range": [3, 5],
		"description": "怪石嶙峋，偏僻幽静，是幽会和密谈的好地方"
	},
	"empty_room": {
		"name": "空置厢房",
		"intel_type": ["dui_shi", "gift_record"],
		"base_rate": 0.45,
		"value_range": [3, 4],
		"description": "无人打理的空房，时常有人在此私下会面"
	}
}

# 活跃会话定时器
var _session_timers: Dictionary = {} # session_id (String) -> Timer
var _completion_check_timer: Timer

# ─────────────────────────────────────────
# 生命周期
# ─────────────────────────────────────────

func _ready() -> void:
	SupabaseManager.realtime_update.connect(_on_realtime_update)
	SupabaseManager.subscribe_to_table("intel_fragments")

	# 创建完成检查定时器（每 30 秒检查一次）
	_completion_check_timer = Timer.new()
	_completion_check_timer.wait_time = 30.0
	_completion_check_timer.timeout.connect(_check_all_sessions_completion)
	_completion_check_timer.autostart = true
	add_child(_completion_check_timer)

	# 恢复活跃会话的定时器（等待 PlayerState 和 GameState 初始化完成）
	await get_tree().create_timer(1.0).timeout
	await _restore_active_sessions()

# ─────────────────────────────────────────
# 实时通知
# ─────────────────────────────────────────

func _on_realtime_update(table_name: String, data: Dictionary) -> void:
	if table_name == "intel_fragments" and data.get("eventType") == "INSERT":
		var record: Dictionary = data.get("new", {})
		if record.get("owner_uid", "") == PlayerState.uid:
			var content: String = record.get("content", "听到了些闲谈。")
			var value_level: int = record.get("value_level", 1)
			var msg: String = "【新情报】" + content
			if EventBus.has_signal("show_notification"):
				EventBus.emit_signal("show_notification", msg)
			intel_received.emit(content, value_level)
			print("[Eavesdrop] Received realtime intel: ", content)

# ─────────────────────────────────────────
# 核心方法 - 开始挂机
# ─────────────────────────────────────────

func start_eavesdrop(player_uid: String, scene: String, duration_hours: int, partner_uid: String = "") -> bool:
	# 1. 检查精力是否足够
	var current_stamina: int = PlayerState.get_current_stamina()
	print("[Eavesdrop] 开始检查精力：当前=%d, 需要=%d" % [current_stamina, COST_STAMINA])

	if current_stamina < COST_STAMINA:
		push_warning("[Eavesdrop] 精力不足：%d < %d" % [current_stamina, COST_STAMINA])
		return false

	print("[Eavesdrop] 精力检查通过")

	# 2. 检查当前游戏 ID 是否有效
	if not GameState.current_game_id or GameState.current_game_id == "":
		push_error("[Eavesdrop] current_game_id is empty!")
		return false

	print("[Eavesdrop] current_game_id: ", GameState.current_game_id)

	# 3. 检查该场景当前人数
	var listener_count: int = await get_scene_listener_count(GameState.current_game_id, scene)
	var success_rate_mod: float = 1.0
	if listener_count >= 5:
		success_rate_mod = 0.5
		print("[Eavesdrop] 场景拥挤，成功率降低到 50%%")
	elif listener_count >= 3:
		success_rate_mod = 0.8
		print("[Eavesdrop] 场景较忙，成功率降低到 80%%")

	print("[Eavesdrop] 场景人数：%d, 成功率修正：%.1f%%" % [listener_count, success_rate_mod * 100])

	# 4. 计算结束时间
	var start_time: int = int(Time.get_unix_time_from_system())
	var end_time: int = start_time + (duration_hours * 3600)

	print("[Eavesdrop] 挂机时长：%d 小时，结束时间：%s" % [duration_hours, Time.get_datetime_string_from_unix_time(end_time)])

	# 5. 构建会话数据
	var session_data: Dictionary = {
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

	print("[Eavesdrop] 会话数据：", session_data)

	# 6. 写入数据库
	print("[Eavesdrop] 插入会话到数据库...")
	var res: Dictionary = await SupabaseManager.insert_into_table("eavesdrop_sessions", session_data)

	print("[Eavesdrop] 数据库返回：code=%d, data=%s" % [res.get("code", -1), str(res.get("data", "null"))])

	if res["code"] != 201:
		push_error("[Eavesdrop] 开启监听失败：" + str(res.get("error", "unknown error")))
		return false

	var session_id: String = res["data"][0]["id"]
	print("[Eavesdrop] 会话创建成功，ID: %s" % session_id)

	# 7. 扣除精力
	print("[Eavesdrop] 扣除精力 %d 点..." % COST_STAMINA)
	if not PlayerState.consume_stamina(COST_STAMINA):
		push_warning("[Eavesdrop] 本地精力扣除失败")
		await SupabaseManager.db_update("eavesdrop_sessions", "id=eq." + session_id, {"status": "cancelled"})
		return false

	print("[Eavesdrop] 精力扣除成功，当前精力：%d" % PlayerState.stamina)

	# 8. 启动定时器
	_start_session_timer(session_id, end_time)

	print("[Eavesdrop] 挂机会话启动成功！")

	# 9. 触发信号
	session_started.emit(session_id)

	return true

# ─────────────────────────────────────────
# 核心方法 - 会话管理
# ─────────────────────────────────────────

func _start_session_timer(session_id: String, end_time: int) -> void:
	var timer: Timer = Timer.new()
	timer.one_shot = true
	timer.wait_time = maxf(1.0, float(end_time - Time.get_unix_time_from_system()))
	timer.timeout.connect(func(): _on_session_timer_timeout(session_id))
	add_child(timer)
	timer.start()
	_session_timers[session_id] = timer

func _on_session_timer_timeout(session_id: String) -> void:
	await check_session_completion(session_id)

func _restore_active_sessions() -> void:
	# 检查 PlayerState 是否已初始化
	if PlayerState.uid == "" or PlayerState.uid == "00000000-0000-0000-0000-000000000000":
		print("[EavesdropManager] _restore_active_sessions skipped: PlayerState.uid not set or invalid")
		return

	# 检查 GameState 是否已初始化
	if GameState.current_game_id == "" or GameState.current_game_id == "00000000-0000-0000-0000-000000000000":
		print("[EavesdropManager] _restore_active_sessions skipped: GameState.current_game_id not set or invalid")
		return

	print("[EavesdropManager] Restoring active sessions for player: ", PlayerState.uid)

	var res: Dictionary = await SupabaseManager.db_get(
		"/rest/v1/eavesdrop_sessions?player_uid=eq.%s&status=eq.active&select=*" % PlayerState.uid
	)
	if res["code"] != 200:
		print("[EavesdropManager] _restore_active_sessions failed: code=", res["code"], ", error=", res.get("error", "unknown"))
		return

	var restored_count: int = 0
	for session in res["data"]:
		var end_time: int = Time.get_unix_time_from_datetime_string(session["ends_at"])
		var now: int = int(Time.get_unix_time_from_system())
		if end_time > now:
			print("[EavesdropManager] Restoring session: ", session["id"], ", ends_at: ", end_time, ", now: ", now)
			_start_session_timer(session["id"], end_time)
			restored_count += 1
		else:
			print("[EavesdropManager] Session already expired: ", session["id"])

	print("[EavesdropManager] Restored ", restored_count, " active sessions")

func _check_all_sessions_completion() -> void:
	# 检查 PlayerState 是否已初始化
	if PlayerState.uid == "" or PlayerState.uid == "00000000-0000-0000-0000-000000000000":
		return

	var res: Dictionary = await SupabaseManager.db_get(
		"/rest/v1/eavesdrop_sessions?player_uid=eq.%s&status=eq.active&select=*" % PlayerState.uid
	)
	if res["code"] != 200:
		return

	for session in res["data"]:
		await check_session_completion(session["id"])

# ─────────────────────────────────────────
# 核心方法 - 情报生成
# ─────────────────────────────────────────

func generate_intel_fragment(session_id: String, force: bool = false) -> void:
	# 1. 获取会话信息
	var res: Dictionary = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] != 200 or res["data"].is_empty():
		return

	var session: Dictionary = res["data"][0]

	# 检查玩家是否被拦截
	var intercept_res: Dictionary = await SupabaseManager.db_get(
		"/rest/v1/intel_intercepts?target_uid=eq.%s&status=eq.active&ends_at=gt.now&select=id" % session["player_uid"]
	)
	if intercept_res["code"] == 200 and not intercept_res["data"].is_empty():
		print("[Eavesdrop] 玩家 ", session["player_uid"], " 被拦截，无法生成情报")
		return

	var scene_key: String = session["scene_key"]
	var config: Dictionary = SCENE_CONFIGS.get(scene_key)
	if not config:
		return

	# 2. 触发率判定（双人挂机有奖励）
	var trigger_rate: float = config["base_rate"] * session["success_rate_mod"]
	if session.get("is_duo", false):
		trigger_rate += DUO_BONUS_RATE

	if not force and randf() > trigger_rate:
		return # 未触发

	# 3. 获取其他玩家最近行动
	var now_minus_48h: String = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 172800)
	var action_res: Dictionary = await SupabaseManager.db_get(
		"/rest/v1/actions?created_at=gt.%s&game_id=eq.%s&select=*" % [now_minus_48h, GameState.current_game_id]
	)

	var intel_content: String = "听到了些琐碎的闲谈，没什么特别的。"
	var intel_type: String = config["intel_type"][randi() % config["intel_type"].size()]

	if action_res["code"] == 200 and not action_res["data"].is_empty():
		var action_data: Dictionary = action_res["data"][randi() % action_res["data"].size()]
		var IntelTemplatesLoader: Script = load("res://features/eavesdrop/IntelTemplates.gd")
		var IntelTemplatesInstance: Node = IntelTemplatesLoader.new()
		intel_content = IntelTemplatesInstance.format_intel(intel_type, action_data)
	else:
		# 无行动记录时使用备用模板
		intel_content = _generate_fallback_intel(intel_type, scene_key)

	# 4. 写入 intel_fragments 表
	var fragment_data: Dictionary = {
		"session_id": session_id,
		"owner_uid": session["player_uid"],
		"game_id": session["game_id"],
		"content": intel_content,
		"intel_type": intel_type,
		"scene_key": scene_key,
		"value_level": randi_range(config["value_range"][0], config["value_range"][1]),
		"status": "unread",
		"is_used": false,
		"is_sold": false
	}

	var frag_res: Dictionary = await SupabaseManager.insert_into_table("intel_fragments", fragment_data)

	# 5. 更新会话结果计数
	var new_count: int = session.get("result_count", 0) + 1
	await SupabaseManager.db_update("eavesdrop_sessions", "id=eq." + session_id, {"result_count": new_count})

	# 6. 对食关系情报共享（只有对食关系才共享）
	if frag_res.get("data") and frag_res["data"].size() > 0:
		var new_intel_id = frag_res["data"][0].get("id", "")
		if new_intel_id != "":
			# 调用 RelationshipManager 共享情报
			var RelManager: Node = Engine.get_singleton("RelationshipManager")
			if RelManager:
				await RelManager.share_intel_with_partner(session["player_uid"], new_intel_id)

	# 7. 双人挂机逻辑：生成双倍碎片
	if session.get("is_duo", false) and session.get("partner_uid", "") != "":
		fragment_data["owner_uid"] = session["partner_uid"]
		fragment_data["value_level"] = mini(fragment_data["value_level"] + DUO_EXTRA_FRAGMENT, 5)
		await SupabaseManager.insert_into_table("intel_fragments", fragment_data)

# 备用情报模板（当 actions 表为空时）
func _generate_fallback_intel(intel_type: String, scene_key: String) -> String:
	var fallbacks: Dictionary = {
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
		],
		"dui_shi": [
			"听见那偏僻处有些奇怪的动静，像是在幽会。",
			"有人在私下议论，说是哪两个小丫鬟在结对食。",
			"瞧见两个影子在假山后头，神神秘秘的。"
		]
	}

	var type_fallbacks: Array = fallbacks.get(intel_type, ["听到了些闲谈。"])
	return type_fallbacks[randi() % type_fallbacks.size()]

# ─────────────────────────────────────────
# 核心方法 - 会话完成
# ─────────────────────────────────────────

func check_session_completion(session_id: String) -> void:
	var res: Dictionary = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] != 200 or res["data"].is_empty():
		return

	var session: Dictionary = res["data"][0]
	if session["status"] != "active":
		return

	var ends_at: int = Time.get_unix_time_from_datetime_string(session["ends_at"])
	var now: int = int(Time.get_unix_time_from_system())

	if ends_at <= now:
		# 更新状态为已完成
		await SupabaseManager.db_update("eavesdrop_sessions", "id=eq." + session_id, {"status": "completed"})

		# 清理定时器
		if _session_timers.has(session_id):
			_session_timers[session_id].queue_free()
			_session_timers.erase(session_id)

		# 统计收获情报数量
		var frag_res: Dictionary = await SupabaseManager.db_get(
			"/rest/v1/intel_fragments?session_id=eq.%s&select=id" % session_id
		)
		var count: int = frag_res["data"].size() if frag_res["code"] == 200 else 0

		# 推送通知
		var scene_name: String = SCENE_CONFIGS.get(session["scene_key"], {}).get("name", session["scene_key"])
		var msg: String = "【挂机完成】你在 [%s] 收获了 %d 条情报" % [scene_name, count]
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", msg)

		session_completed.emit(session_id, count)

# ─────────────────────────────────────────
# 公共方法
# ─────────────────────────────────────────

func get_scene_listener_count(game_id: String, scene: String) -> int:
	# 检查 game_id 是否有效
	if not game_id or game_id == "" or game_id == "00000000-0000-0000-0000-000000000000":
		print("[EavesdropManager] get_scene_listener_count: invalid game_id=", game_id)
		return 0

	var endpoint: String = "/rest/v1/eavesdrop_sessions?game_id=eq.%s&scene_key=eq.%s&status=eq.active&select=id" % [game_id, scene]
	var res: Dictionary = await SupabaseManager.db_get(endpoint)
	if res["code"] == 200 and res["data"] is Array:
		return res["data"].size()
	print("[EavesdropManager] get_scene_listener_count failed: code=", res.get("code", -1), ", data type=", typeof(res.get("data", null)))
	return 0

func get_active_sessions() -> Array:
	# 检查 PlayerState.uid 是否有效
	if PlayerState.uid == "" or PlayerState.uid == "00000000-0000-0000-0000-000000000000":
		print("[EavesdropManager] get_active_sessions: invalid PlayerState.uid=", PlayerState.uid)
		return []

	var res: Dictionary = await SupabaseManager.db_get(
		"/rest/v1/eavesdrop_sessions?player_uid=eq.%s&status=eq.active&select=*" % PlayerState.uid
	)
	print("[EavesdropManager] get_active_sessions result: code=", res.get("code", -1), ", data=", res.get("data", "N/A"))
	if res["code"] == 200 and res["data"] is Array:
		return res["data"]
	print("[EavesdropManager] get_active_sessions failed: code=", res.get("code", -1), ", data type=", typeof(res.get("data", null)))
	return []

func get_session_time_remaining(session_id: String) -> int:
	var session: Dictionary = await _get_session(session_id)
	if session.is_empty():
		return 0
	var ends_at: int = Time.get_unix_time_from_datetime_string(session["ends_at"])
	var remaining: int = ends_at - Time.get_unix_time_from_system()
	return maxi(0, remaining)

func _get_session(session_id: String) -> Dictionary:
	var res: Dictionary = await SupabaseManager.db_get("/rest/v1/eavesdrop_sessions?id=eq.%s&select=*" % session_id)
	if res["code"] == 200 and not res["data"].is_empty():
		return res["data"][0]
	return {}

func cancel_session(session_id: String) -> bool:
	var session: Dictionary = await _get_session(session_id)
	if session.is_empty():
		return false

	# 只能取消未完成的会话
	if session["status"] != "active":
		return false

	# 更新状态
	var res: Dictionary = await SupabaseManager.db_update(
		"eavesdrop_sessions",
		"id=eq." + session_id,
		{"status": "cancelled"}
	)

	# 清理定时器
	if _session_timers.has(session_id):
		_session_timers[session_id].queue_free()
		_session_timers.erase(session_id)

	return res["code"] == 200
