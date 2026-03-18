extends Node

# DuiShiEvents.gd
# 对食关系特殊事件和对话系统

signal dui_shi_event_triggered(event_name: String, event_data: Dictionary)

# 对食关系特殊事件配置
const DUISHI_EVENTS = {
	"exchange_gift": {
		"name": "交换信物",
		"description": "与对食搭档交换私密信物，增进感情",
		"trigger_chance": 0.15,  # 15% 触发几率
		"effects": {
			"relationship_bonus": 5,  # 关系加成
			"intel_bonus": 0.1  # 情报获取加成 10%
		}
	},
	"secret_meeting": {
		"name": "私下幽会",
		"description": "在偏僻处与对食搭档秘密相会",
		"trigger_chance": 0.2,
		"effects": {
			"relationship_bonus": 3,
			"mood_bonus": 10
		}
	},
	"share_secret": {
		"name": "分享秘密",
		"description": "向对食搭档倾诉内心秘密",
		"trigger_chance": 0.25,
		"effects": {
			"relationship_bonus": 8,
			"stress_relief": 5
		}
	},
	"defend_partner": {
		"name": "维护搭档",
		"description": "在他人面前维护对食搭档",
		"trigger_chance": 0.1,
		"effects": {
			"face_value": 5,
			"relationship_bonus": 10
		}
	}
}

# 对食关系对话模板
const DUISHI_DIALOGUES = {
	"greeting": [
		"今儿个可好？我这儿有件新鲜事儿想跟你说。",
		"可算找着你了，这几日可把我闷坏了。",
		"你来了？我正想着你呢。"
	],
	"care": [
		"这几日天凉，你可要多加件衣裳。",
		"听说你昨儿个累着了，可还撑得住？",
		"我留了些好点心，给你藏着呢。"
	],
	"encourage": [
		"别怕，有我在呢，咱们互相照应着。",
		"你且安心做事，外头的闲言碎语别理他们。",
		"咱们既结了对食，便要同心协力才是。"
	],
	"warning": [
		"我听说有人在背后议论咱们，你须得小心。",
		"那边的管家最近查得紧，咱们行事要更隐秘些。",
		"最近风声紧，你且收敛些，别叫人拿了把柄。"
	],
	"farewell": [
		"天色不早了，你且回去歇着，改日再会。",
		"我先回去了，你自保重。",
		"改日再会，你且记着我说的话。"
	]
}

# 检查并触发对食特殊事件
func check_and_trigger_event(player_uid: String, partner_uid: String) -> void:
	var relationship = await _get_relationship(player_uid, partner_uid)
	if relationship.is_empty():
		return
	
	# 遍历所有事件，按概率触发
	for event_key in DUISHI_EVENTS.keys():
		var event_config = DUISHI_EVENTS[event_key]
		var trigger_chance = event_config.get("trigger_chance", 0.1)
		
		if randf() < trigger_chance:
			await _trigger_event(event_key, event_config, player_uid, partner_uid)
			break

# 触发特定事件
func _trigger_event(event_key: String, event_config: Dictionary, player_uid: String, partner_uid: String) -> void:
	print("[DuiShiEvents] Triggering event: ", event_key)
	
	# 获取搭档名称
	var partner_name = await _get_player_name(partner_uid)
	
	var event_data = {
		"event_name": event_config["name"],
		"description": event_config["description"],
		"effects": event_config["effects"],
		"partner_name": partner_name,
		"triggered_at": Time.get_datetime_string_from_system(false, true)
	}
	
	# 发送信号通知 UI 显示事件
	dui_shi_event_triggered.emit(event_key, event_data)
	
	# 记录事件到数据库
	await _record_event(player_uid, event_key, event_data)
	
	# 应用事件效果
	await _apply_event_effects(player_uid, event_config["effects"])

# 获取随机对话
func get_random_dialogue(dialogue_type: String) -> String:
	if not DUISHI_DIALOGUES.has(dialogue_type):
		return ""
	
	var dialogues = DUISHI_DIALOGUES[dialogue_type]
	return dialogues[randi() % dialogues.size()]

# 获取关系数据
func _get_relationship(player_uid: String, partner_uid: String) -> Dictionary:
	var query = "/rest/v1/maid_relationships?or=(player_a_uid.eq.%s,player_b_uid.eq.%s)&relation_type=eq.dui_shi&status=eq.active&select=*" % [player_uid, partner_uid]
	var res = await SupabaseManager.db_get(query)
	if res["code"] == 200 and not res["data"].is_empty():
		return res["data"][0]
	return {}

# 获取玩家名称
func _get_player_name(player_uid: String) -> String:
	var res = await SupabaseManager.db_get("/rest/v1/players?id=eq.%s&select=character_name" % player_uid)
	if res["code"] == 200 and not res["data"].is_empty():
		return res["data"][0].get("character_name", "未知")
	return "未知"

# 记录事件到数据库
func _record_event(player_uid: String, event_key: String, event_data: Dictionary) -> void:
	var event_record = {
		"player_uid": player_uid,
		"event_type": "dui_shi_" + event_key,
		"event_name": event_data["event_name"],
		"description": event_data["description"],
		"created_at": event_data["triggered_at"]
	}
	await SupabaseManager.db_insert("event_logs", event_record)

# 应用事件效果
func _apply_event_effects(player_uid: String, effects: Dictionary) -> void:
	# 这里可以根据需要实现各种效果
	# 目前仅做简单实现
	
	if effects.has("face_value"):
		# 体面值变化
		var current_face = PlayerState.face_value
		PlayerState.face_value = current_face + effects["face_value"]
		await SupabaseManager.db_update("players", "id=eq." + player_uid, {"face_value": PlayerState.face_value})
	
	# 其他效果可以在未来扩展
	EventBus.show_notification.emit("对食事件触发：获得特殊效果加成")
