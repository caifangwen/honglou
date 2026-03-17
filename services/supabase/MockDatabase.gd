extends Node

# 本地测试模式 - 模拟数据库操作
# 用于在没有网络连接时测试 UI 功能

var _mock_rumors: Array = []
var _mock_players: Array = []
var _mock_games: Array = []

signal mock_operation_completed(operation: String, data: Dictionary)

func _ready():
	print("[MockDatabase] Initialized")
	_init_mock_data()

func _init_mock_data():
	# 创建测试游戏
	_mock_games.append({
		"id": "00000000-0000-0000-0000-000000000001",
		"status": "active"
	})
	
	# 创建测试玩家
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
		"username": "pinger",
		"display_name": "平儿",
		"role_class": "steward",
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
