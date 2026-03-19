extends Node

# 本地测试模式 - 模拟数据库操作
# 用于在没有网络连接时测试 UI 功能

var _mock_rumors: Array = []
var _mock_players: Array = []
var _mock_games: Array = []
var _mock_maid_relationships: Array = []  # 对食关系模拟数据
var _mock_notifications: Array = []  # 通知模拟数据

signal mock_operation_completed(operation: String, data: Dictionary)

func _ready():
	print("[MockDatabase] Initialized")
	_init_mock_data()

func _init_mock_data():
	# 只在数组为空时初始化测试数据（避免重置已存储的数据）
	if _mock_games.is_empty():
		_mock_games.append({
			"id": "00000000-0000-0000-0000-000000000001",
			"status": "active"
		})

	if _mock_players.is_empty():
		_mock_players.append({
			"id": "11111111-1111-1111-1111-111111111111",
			"auth_uid": "test-auth-uid",
			"username": "fengjie",
			"display_name": "凤姐",
			"role_class": "steward",
			"current_game_id": "00000000-0000-0000-0000-000000000001",
			"stamina": 6
		})
		_mock_players.append({
			"id": "55555555-5555-5555-5555-555555555555",
			"auth_uid": "test-auth-uid-2",
			"username": "qingwen",
			"display_name": "晴雯姑娘",
			"character_name": "晴雯",
			"role_class": "servant",  # 改为 servant 以支持对食功能
			"current_game_id": "00000000-0000-0000-0000-000000000001",
			"stamina": 6
		})
		_mock_players.append({
			"id": "44444444-4444-4444-4444-444444444444",
			"auth_uid": "test-auth-uid-3",
			"username": "pinger",
			"display_name": "平儿",
			"character_name": "平儿",
			"role_class": "servant",
			"current_game_id": "00000000-0000-0000-0000-000000000001",
			"stamina": 6
		})

func mock_insert_rumor(data: Dictionary) -> Dictionary:
	await get_tree().create_timer(0.1).timeout # 模拟网络延迟
	
	var new_rumor = data.duplicate()
	new_rumor["id"] = _generate_uuid()
	new_rumor["created_at"] = Time.get_datetime_string_from_system()
	
	# 添加 target_player 信息（模拟关联查询结果）
	var target_player = _mock_players.filter(func(p): return p["id"] == data.get("target_uid"))
	if target_player.size() > 0:
		new_rumor["target_player"] = [{
			"display_name": target_player[0]["display_name"],
			"id": target_player[0]["id"]
		}]
	
	_mock_rumors.append(new_rumor)
	
	print("[MockDatabase] Inserted rumor: ", new_rumor["id"])
	print("[MockDatabase] Rumor data: ", new_rumor)
	mock_operation_completed.emit("insert_rumor", new_rumor)
	
	return {
		"code": 201,
		"data": [new_rumor],
		"error": null
	}

func mock_select_rumors(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.1).timeout
	
	var result = _mock_rumors.filter(func(r):
		for key in filters.keys():
			if r.get(key) != filters[key]:
				return false
		return true
	)
	
	print("[MockDatabase] Selected %d rumors" % result.size())
	return result

func mock_update_player(player_id: String, data: Dictionary) -> Dictionary:
	for p in _mock_players:
		if p["id"] == player_id:
			for key in data.keys():
				p[key] = data[key]
			print("[MockDatabase] Updated player: ", player_id)
			return {"code": 200, "data": [p]}
	
	return {"code": 404, "error": "Player not found"}

func _generate_uuid() -> String:
	return "%08x-%04x-%04x-%04x-%012x" % [
		randi() % 0xFFFFFFFF,
		randi() % 0xFFFF,
		randi() % 0xFFFF,
		randi() % 0xFFFF,
		randi() % 0xFFFFFFFFFFFF
	]

func get_mock_rumors() -> Array:
	return _mock_rumors.duplicate()

func clear_mock_data():
	_mock_rumors.clear()
	print("[MockDatabase] Cleared all mock data")

# ─────────────────────────────────────────
# maid_relationships 表操作
# ─────────────────────────────────────────

func mock_insert_maid_relationship(data: Dictionary) -> Dictionary:
	await get_tree().create_timer(0.1).timeout

	var new_rel = data.duplicate()
	new_rel["id"] = _generate_uuid()
	new_rel["created_at"] = Time.get_datetime_string_from_system()
	new_rel["game_id"] = "00000000-0000-0000-0000-000000000001"

	_mock_maid_relationships.append(new_rel)

	print("[MockDatabase] Inserted maid_relationship: ", new_rel["id"])
	print("[MockDatabase] Relationship data: ", new_rel)

	return {
		"code": 201,
		"data": [new_rel],
		"error": null
	}

func mock_select_maid_relationships(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.05).timeout
	
	print("[MockDatabase] mock_select_maid_relationships - filters: ", filters)
	print("[MockDatabase] Total relationships in mock: ", _mock_maid_relationships.size())

	var result = _mock_maid_relationships.filter(func(r):
		for key in filters.keys():
			if key == "player_b_uid":
				if r.get("player_b_uid") != filters[key]:
					return false
			elif key == "status":
				if r.get("status") != filters[key]:
					return false
			elif key == "relation_type":
				if r.get("relation_type") != filters[key]:
					return false
			elif key == "id":
				if r.get("id") != filters[key]:
					return false
		return true
	)
	
	print("[MockDatabase] Filtered relationships count: ", result.size())

	# 处理关联查询（player_a 和 player_b）
	var expanded_result = []
	for rel in result:
		var expanded_rel = rel.duplicate()
		# 查找 player_a 信息
		var player_a = _mock_players.filter(func(p): return p["id"] == rel.get("player_a_uid"))
		if player_a.size() > 0:
			expanded_rel["player_a"] = [{"character_name": player_a[0]["display_name"], "id": player_a[0]["id"]}]
		# 查找 player_b 信息
		var player_b = _mock_players.filter(func(p): return p["id"] == rel.get("player_b_uid"))
		if player_b.size() > 0:
			expanded_rel["player_b"] = [{"character_name": player_b[0]["display_name"], "id": player_b[0]["id"]}]
		expanded_result.append(expanded_rel)

	print("[MockDatabase] Selected %d maid_relationships" % result.size())
	return expanded_result

# ─────────────────────────────────────────
# notifications 表操作
# ─────────────────────────────────────────

func mock_insert_notification(data: Dictionary) -> Dictionary:
	await get_tree().create_timer(0.05).timeout

	var new_notification = data.duplicate()
	new_notification["id"] = _generate_uuid()
	new_notification["created_at"] = Time.get_datetime_string_from_system()

	_mock_notifications.append(new_notification)

	print("[MockDatabase] Inserted notification: ", new_notification["id"])
	print("[MockDatabase] Notification content: ", new_notification.get("content"))

	return {
		"code": 201,
		"data": [new_notification],
		"error": null
	}

func mock_select_notifications(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.05).timeout

	var result = _mock_notifications.filter(func(n):
		for key in filters.keys():
			if key == "player_uid":
				if n.get("player_uid") != filters[key]:
					return false
		return true
	)

	print("[MockDatabase] Selected %d notifications" % result.size())
	return result
