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

	# 初始化所有测试角色（15 个）
	if _mock_players.is_empty():
		_init_test_players()

func _init_test_players():
	# 管家（2 人）
	_mock_players.append({
		"id": "11111111-1111-1111-1111-111111111111",
		"auth_uid": "11111111-1111-1111-1111-111111111111",
		"username": "fengjie",
		"display_name": "凤辣子",
		"character_name": "王熙凤",
		"role_class": "steward",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 100,
		"private_silver": 500
	})
	_mock_players.append({
		"id": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
		"auth_uid": "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
		"username": "pingr",
		"display_name": "平儿姑娘",
		"character_name": "平儿",
		"role_class": "steward",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 15,
		"private_silver": 200
	})
	# 主子（6 人）
	_mock_players.append({
		"id": "22222222-2222-2222-2222-222222222222",
		"auth_uid": "22222222-2222-2222-2222-222222222222",
		"username": "baoyu",
		"display_name": "宝二爷",
		"character_name": "贾宝玉",
		"role_class": "master",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 50
	})
	_mock_players.append({
		"id": "33333333-3333-3333-3333-333333333333",
		"auth_uid": "33333333-3333-3333-3333-333333333333",
		"username": "daiyu",
		"display_name": "林姑娘",
		"character_name": "林黛玉",
		"role_class": "master",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 30
	})
	_mock_players.append({
		"id": "66666666-6666-6666-6666-666666666666",
		"auth_uid": "66666666-6666-6666-6666-666666666666",
		"username": "baochai",
		"display_name": "宝姑娘",
		"character_name": "薛宝钗",
		"role_class": "master",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 40
	})
	_mock_players.append({
		"id": "77777777-7777-7777-7777-777777777777",
		"auth_uid": "77777777-7777-7777-7777-777777777777",
		"username": "yingchun",
		"display_name": "二姑娘",
		"character_name": "贾迎春",
		"role_class": "master",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 25
	})
	_mock_players.append({
		"id": "88888888-8888-8888-8888-888888888888",
		"auth_uid": "88888888-8888-8888-8888-888888888888",
		"username": "tanchun",
		"display_name": "三姑娘",
		"character_name": "贾探春",
		"role_class": "master",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 35
	})
	_mock_players.append({
		"id": "99999999-9999-9999-9999-999999999999",
		"auth_uid": "99999999-9999-9999-9999-999999999999",
		"username": "xichun",
		"display_name": "四姑娘",
		"character_name": "贾惜春",
		"role_class": "master",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 20
	})
	# 丫鬟（5 人）
	_mock_players.append({
		"id": "44444444-4444-4444-4444-444444444444",
		"auth_uid": "44444444-4444-4444-4444-444444444444",
		"username": "xiren",
		"display_name": "袭人姑娘",
		"character_name": "袭人",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 10
	})
	_mock_players.append({
		"id": "55555555-5555-5555-5555-555555555555",
		"auth_uid": "55555555-5555-5555-5555-555555555555",
		"username": "qingwen",
		"display_name": "晴雯姑娘",
		"character_name": "晴雯",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 5
	})
	_mock_players.append({
		"id": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
		"auth_uid": "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb",
		"username": "yuanyang",
		"display_name": "鸳鸯姑娘",
		"character_name": "鸳鸯",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 20
	})
	_mock_players.append({
		"id": "cccccccc-cccc-cccc-cccc-cccccccccccc",
		"auth_uid": "cccccccc-cccc-cccc-cccc-cccccccccccc",
		"username": "zijuan",
		"display_name": "紫鹃姑娘",
		"character_name": "紫鹃",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 8
	})
	_mock_players.append({
		"id": "ffffffff-ffff-ffff-ffff-ffffffffffff",
		"auth_uid": "ffffffff-ffff-ffff-ffff-ffffffffffff",
		"username": "mili",
		"display_name": "麝月姑娘",
		"character_name": "麝月",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 7
	})
	# 小厮（2 人）
	_mock_players.append({
		"id": "11111110-1111-1111-1111-111111111111",
		"auth_uid": "11111110-1111-1111-1111-111111111111",
		"username": "mingyan",
		"display_name": "茗烟",
		"character_name": "茗烟",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 8
	})
	_mock_players.append({
		"id": "33333330-3333-3333-3333-333333333333",
		"auth_uid": "33333330-3333-3333-3333-333333333333",
		"username": "xingr",
		"display_name": "兴儿",
		"character_name": "兴儿",
		"role_class": "servant",
		"current_game_id": "00000000-0000-0000-0000-000000000001",
		"stamina": 6,
		"silver": 5
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

func mock_select_players(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.05).timeout
	
	print("[MockDatabase] mock_select_players - filters: ", filters)
	print("[MockDatabase] Total players in mock: ", _mock_players.size())
	
	var result = _mock_players.filter(func(p):
		for key in filters.keys():
			if p.get(key) != filters[key]:
				return false
		return true
	)
	
	print("[MockDatabase] Filtered players count: ", result.size())
	return result

func mock_select_steward_accounts(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.05).timeout
	
	print("[MockDatabase] mock_select_steward_accounts - filters: ", filters)
	print("[MockDatabase] Total steward_accounts in mock: ", _mock_steward_accounts.size())
	
	# 如果没有数据，创建一个默认的管家账本
	if _mock_steward_accounts.is_empty() and filters.get("steward_uid"):
		var default_account = {
			"id": _generate_uuid(),
			"game_id": filters.get("game_id", "00000000-0000-0000-0000-000000000001"),
			"steward_uid": filters.get("steward_uid"),
			"public_ledger": [],
			"private_ledger": [],
			"private_assets": 500,
			"prestige": 80,
			"route": "undecided"
		}
		_mock_steward_accounts.append(default_account)
		print("[MockDatabase] Created default steward account")
	
	var result = _mock_steward_accounts.filter(func(a):
		for key in filters.keys():
			if a.get(key) != filters[key]:
				return false
		return true
	)
	
	print("[MockDatabase] Filtered steward_accounts count: ", result.size())
	return result

func mock_select_treasury(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.05).timeout
	
	print("[MockDatabase] mock_select_treasury - filters: ", filters)
	
	# 创建一个默认的银库数据
	var default_treasury = {
		"game_id": filters.get("game_id", "00000000-0000-0000-0000-000000000001"),
		"total_silver": 50000,
		"daily_budget": 2000,
		"public_balance": 50000,
		"real_balance": 50000,
		"prosperity_level": 8,
		"deficit_rate": 0.0
	}
	
	print("[MockDatabase] Returning default treasury data")
	return [default_treasury]

func mock_select_allowance_records(filters: Dictionary) -> Array:
	await get_tree().create_timer(0.05).timeout
	
	print("[MockDatabase] mock_select_allowance_records - filters: ", filters)
	print("[MockDatabase] Total allowance_records in mock: ", _mock_allowance_records.size())
	
	var result = _mock_allowance_records.filter(func(r):
		for key in filters.keys():
			if r.get(key) != filters[key]:
				return false
		return true
	)
	
	print("[MockDatabase] Filtered allowance_records count: ", result.size())
	return result

func mock_insert_steward_accounts(data: Dictionary) -> Dictionary:
	await get_tree().create_timer(0.05).timeout
	
	var new_account = data.duplicate()
	new_account["id"] = _generate_uuid()
	new_account["created_at"] = Time.get_datetime_string_from_system()
	
	_mock_steward_accounts.append(new_account)
	
	print("[MockDatabase] Inserted steward_account: ", new_account["id"])
	
	return {
		"code": 201,
		"data": [new_account],
		"error": null
	}

func mock_insert_allowance_records(data: Dictionary) -> Dictionary:
	await get_tree().create_timer(0.05).timeout
	
	var new_record = data.duplicate()
	new_record["id"] = _generate_uuid()
	new_record["created_at"] = Time.get_datetime_string_from_system()
	
	_mock_allowance_records.append(new_record)
	
	print("[MockDatabase] Inserted allowance_record")
	
	return {
		"code": 201,
		"data": [new_record],
		"error": null
	}

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

# ─────────────────────────────────────────
# RPC 函数模拟
# ─────────────────────────────────────────

var _mock_steward_accounts: Array = []
var _mock_allowance_records: Array = []

func db_rpc(function_name: String, params: Dictionary = {}, with_auth: bool = true) -> Dictionary:
	await get_tree().create_timer(0.1).timeout
	
	print("[MockDatabase] RPC called: ", function_name, " with params: ", params)
	
	match function_name:
		"distribute_allowance_rpc":
			return await _mock_distribute_allowance_rpc(params)
		"bulk_distribute_allowance_rpc":
			return await _mock_bulk_distribute_allowance_rpc(params)
		"get_treasury_stats":
			return await _mock_get_treasury_stats(params)
		"steward_assign_task":
			return await _mock_steward_assign_task(params)
		"steward_procure_goods":
			return await _mock_steward_procure_goods(params)
		"steward_search_players":
			return await _mock_steward_search_players(params)
		"steward_advance_credit":
			return await _mock_steward_advance_credit(params)
		"steward_suppress_rumor":
			return await _mock_steward_suppress_rumor(params)
		"steward_block_intel":
			return await _mock_steward_block_intel(params)
		_:
			print("[MockDatabase] Unknown RPC function: ", function_name)
			# 返回成功响应，用于未知函数
			return {"code": 200, "data": {"success": true}}

# 模拟 distribute_allowance_rpc
func _mock_distribute_allowance_rpc(params: Dictionary) -> Dictionary:
	var p_steward_uid = params.get("p_steward_uid", "")
	var p_recipient_uid = params.get("p_recipient_uid", "")
	var p_recipient_name = params.get("p_recipient_name", "未知")
	var p_actual_amount = int(params.get("p_actual_amount", 20))
	var p_standard_amount = int(params.get("p_standard_amount", 20))
	var p_game_id = params.get("p_game_id", "00000000-0000-0000-0000-000000000001")
	
	var v_withheld = p_standard_amount - p_actual_amount
	
	# 更新玩家银两
	for p in _mock_players:
		if p["id"] == p_recipient_uid:
			p["silver"] = p.get("silver", 0) + p_actual_amount
			if v_withheld > 0:
				p["private_silver"] = p.get("private_silver", 0) + v_withheld
			break
	
	# 记录发放记录
	var record = {
		"id": _generate_uuid(),
		"game_id": p_game_id,
		"player_id": p_recipient_uid,
		"issued_by": p_steward_uid,
		"amount_public": p_standard_amount,
		"amount_actual": p_actual_amount,
		"withheld_amount": v_withheld,
		"issued_at": Time.get_datetime_string_from_system()
	}
	_mock_allowance_records.append(record)
	
	print("[MockDatabase] Distributed allowance: ", p_recipient_name, " actual=", p_actual_amount, " withheld=", v_withheld)
	
	return {
		"code": 200,
		"data": {
			"success": true,
			"withheld": v_withheld,
			"new_deficit": 0.0
		}
	}

# 模拟 bulk_distribute_allowance_rpc
func _mock_bulk_distribute_allowance_rpc(params: Dictionary) -> Dictionary:
	var p_steward_uid = params.get("p_steward_uid", "")
	var p_game_id = params.get("p_game_id", "00000000-0000-0000-0000-000000000001")
	var p_distributions = params.get("p_distributions", [])
	
	var total_withheld = 0
	var success_count = 0
	
	for dist in p_distributions:
		var recipient_uid = dist.get("recipient_uid", "")
		var recipient_name = dist.get("recipient_name", "未知")
		var actual = int(dist.get("actual_amount", 20))
		var standard = int(dist.get("standard_amount", 20))
		var withheld = standard - actual
		
		# 更新玩家银两
		for p in _mock_players:
			if p["id"] == recipient_uid:
				p["silver"] = p.get("silver", 0) + actual
				if withheld > 0:
					p["private_silver"] = p.get("private_silver", 0) + withheld
				break
		
		total_withheld += withheld
		success_count += 1
		
		# 记录
		var record = {
			"id": _generate_uuid(),
			"game_id": p_game_id,
			"player_id": recipient_uid,
			"issued_by": p_steward_uid,
			"amount_public": standard,
			"amount_actual": actual,
			"withheld_amount": withheld,
			"issued_at": Time.get_datetime_string_from_system()
		}
		_mock_allowance_records.append(record)
	
	print("[MockDatabase] Bulk distributed allowance: count=", success_count, " total_withheld=", total_withheld)
	
	return {
		"code": 200,
		"data": {
			"success": true,
			"total_withheld": total_withheld,
			"success_count": success_count
		}
	}

# 模拟 get_treasury_stats
func _mock_get_treasury_stats(params: Dictionary) -> Dictionary:
	var sum_public = 0
	var sum_withheld = 0
	
	for record in _mock_allowance_records:
		sum_public += record.get("amount_public", 0)
		sum_withheld += record.get("withheld_amount", 0)
	
	return {
		"code": 200,
		"data": [{
			"sum_public": sum_public,
			"sum_withheld": sum_withheld
		}]
	}

# 模拟 steward_assign_task (差事分派)
func _mock_steward_assign_task(params: Dictionary) -> Dictionary:
	var p_target_uid = params.get("p_target_uid", "")
	var p_silver_reward = int(params.get("p_silver_reward", 10))
	var p_task_type = params.get("p_task_type", "errand")
	
	var stamina_drain = 2
	var message_content = "你被派去办理一桩差事，略感辛劳，却得了些许赏银。"
	
	match p_task_type:
		"errand": stamina_drain = 2
		"guard": stamina_drain = 1
		"purchase": stamina_drain = 3
		"message": stamina_drain = 2
		"clean": stamina_drain = 2
		"special": stamina_drain = 4
	
	# 更新目标玩家
	for p in _mock_players:
		if p["id"] == p_target_uid:
			p["silver"] = p.get("silver", 0) + p_silver_reward
			p["stamina"] = max(0, p.get("stamina", 6) - stamina_drain)
			break
	
	print("[MockDatabase] Assigned task: target=", p_target_uid, " type=", p_task_type, " reward=", p_silver_reward)
	
	return {
		"code": 200,
		"data": {
			"success": true,
			"target_silver": p_silver_reward,
			"target_stamina": stamina_drain,
			"task_type": p_task_type,
			"stamina_drain": stamina_drain
		}
	}

# 模拟其他 RPC 函数（返回成功）
func _mock_steward_procure_goods(params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {"success": true, "ticket_id": _generate_uuid()}}

func _mock_steward_search_players(params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {"success": true, "found_count": 5}}

func _mock_steward_advance_credit(params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {"success": true}}

func _mock_steward_suppress_rumor(params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {"success": true}}

func _mock_steward_block_intel(params: Dictionary) -> Dictionary:
	return {"code": 200, "data": {"success": true}}
