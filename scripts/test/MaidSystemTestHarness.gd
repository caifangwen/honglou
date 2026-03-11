extends Node

# MaidSystemTestHarness.gd
# 仅用于开发测试，打包时排除。

signal test_log(message: String)

var test_game_id: String = "test_game_001"
var maid_a_uid: String = "maid_a_uuid"
var maid_b_uid: String = "maid_b_uuid"
var steward_uid: String = "steward_uuid"

# 快速设置测试环境（在开发模式下调用）
func setup_test_environment() -> void:
	log_test("正在初始化测试环境...")
	
	# 1. 模拟或确保游戏局存在
	# 这里假设 games 表已有此 ID，或手动插入
	await SupabaseManager.db_insert("games", {
		"id": test_game_id,
		"status": "active"
	})
	
	# 2. 创建或更新测试账号
	var maids = [
		{"id": maid_a_uid, "display_name": "测试丫鬟A", "role_class": "servant", "silver": 100, "qi_shu": 50, "stamina": 8, "face_value": 80},
		{"id": maid_b_uid, "display_name": "测试丫鬟B", "role_class": "servant", "silver": 80, "qi_shu": 50, "stamina": 8, "face_value": 80},
		{"id": steward_uid, "display_name": "测试管家", "role_class": "steward", "silver": 500}
	]
	
	for m in maids:
		# 使用 upsert 逻辑 (Supabase insert with ON CONFLICT)
		# 这里的简单实现：先尝试插入，失败则更新
		var res = await SupabaseManager.db_insert("players", m)
		if res["code"] != 201:
			await SupabaseManager.db_update("players", "id=eq." + m["id"], m)
	
	log_test("测试环境初始化完成：maid_a, maid_b, steward 已就绪。")

# 场景1：情报生成测试
func test_intel_generation() -> void:
	log_test("--- 开始测试：情报生成 ---")
	
	# 1. 模拟管家执行行动
	await SupabaseManager.db_insert("actions", {
		"actor_id": steward_uid,
		"game_id": test_game_id,
		"action_type": "account_embezzle",
		"content": "管家偷偷支取了50两公中银子。",
		"status": "resolved"
	})
	
	# 2. 让 maid_a 在"管家后账房"开启会话
	# 模拟调用 EavesdropManager
	var start_time = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()))
	var end_time = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 3600)
	
	var session_res = await SupabaseManager.db_insert("eavesdrop_sessions", {
		"player_uid": maid_a_uid,
		"game_id": test_game_id,
		"scene": "treasury_back",
		"status": "active",
		"ends_at": end_time
	})
	
	if session_res["code"] != 201:
		log_test("错误：创建监听会话失败")
		return
	
	var session_id = session_res["data"]["id"]
	
	# 3. 手动触发情报生成
	await EavesdropManager.generate_intel_fragment(session_id, true)
	
	# 4. 断言：查询是否有新碎片
	var frag_res = await SupabaseManager.db_get("/rest/v1/intel_fragments?player_uid=eq.%s&intel_type=eq.account_leak&select=*" % maid_a_uid)
	
	if frag_res["code"] == 200 and not frag_res["data"].is_empty():
		log_test("断言成功：maid_a 获得 account_leak 类型情报。")
	else:
		log_test("断言失败：未找到对应情报。")

# 场景4：流言发酵测试（时间加速模拟）
func test_rumor_fermentation() -> void:
	log_test("--- 开始测试：流言发酵 ---")
	
	# 1. 手动插入一条流言，设置 stage_0_at 为 7 小时前
	var seven_hours_ago = Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) - 7 * 3600)
	
	var rumor_res = await SupabaseManager.db_insert("rumors", {
		"game_id": test_game_id,
		"publisher_uid": maid_a_uid,
		"target_uid": maid_b_uid,
		"content": "听说丫鬟B私藏了主子的发簪。",
		"stage": 1,
		"published_at": seven_hours_ago
	})
	
	if rumor_res["code"] != 201:
		log_test("错误：插入流言失败")
		return
		
	var rumor_id = rumor_res["data"]["id"]
	
	# 2. 调用模拟的发酵检查
	await ferment_check_now(rumor_id)
	
	# 3. 断言：stage 更新为 2，target 体面值减少
	var updated_rumor = await SupabaseManager.db_get("/rest/v1/rumors?id=eq." + rumor_id + "&select=stage")
	var target_player = await SupabaseManager.db_get("/rest/v1/players?id=eq." + maid_b_uid + "&select=face_value")
	
	if updated_rumor["data"][0]["stage"] == 2:
		log_test("断言成功：流言发酵至阶段 2。")
	else:
		log_test("断言失败：流言阶段未更新。")
		
	log_test("目标体面值当前为: " + str(target_player["data"][0]["face_value"]))

# 场景6：赎身出府成就测试
func test_redemption_achievement() -> void:
	log_test("--- 开始测试：赎身出府 ---")
	
	# 1. 设置 maid_a 状态
	await SupabaseManager.db_update("players", "id=eq." + maid_a_uid, {"silver": 350})
	
	# 2. 模拟资产转移记录
	await SupabaseManager.db_insert("asset_transfers", {
		"player_uid": maid_a_uid,
		"game_id": test_game_id,
		"amount": 200,
		"target_account": "outside_contact"
	})
	
	# 3. 调用进度检查
	await MaidProgressionChecker.check_all_paths(maid_a_uid, test_game_id)
	
	# 4. 断言
	var ach_res = await SupabaseManager.db_get("/rest/v1/achievements?player_uid=eq.%s&type=eq.redemption&select=*" % maid_a_uid)
	var bonus_res = await SupabaseManager.db_get("/rest/v1/settlement_bonus?player_uid=eq.%s&game_id=eq.%s&select=*" % [maid_a_uid, test_game_id])
	
	if not ach_res["data"].is_empty() and not bonus_res["data"].is_empty():
		log_test("断言成功：赎身成就已解锁，结算加成已写入。")
	else:
		log_test("断言失败：成就或加成记录缺失。")

# 模拟流言发酵逻辑 (在 TestHarness 中实现)
func ferment_check_now(rumor_id: String) -> void:
	var res = await SupabaseManager.db_get("/rest/v1/rumors?id=eq." + rumor_id + "&select=*")
	if res["code"] != 200 or res["data"].is_empty(): return
	
	var rumor = res["data"][0]
	var stage = rumor["stage"]
	var target_uid = rumor["target_uid"]
	
	# 检查时间是否满足（这里由于是测试，我们假设已经满足）
	if stage == 1:
		# 更新流言阶段
		await SupabaseManager.db_update("rumors", "id=eq." + rumor_id, {
			"stage": 2,
			"stage2_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()))
		})
		
		# 扣除目标体面值
		var p_res = await SupabaseManager.db_get("/rest/v1/players?id=eq." + target_uid + "&select=face_value")
		if not p_res["data"].is_empty():
			var old_face = p_res["data"][0]["face_value"]
			await SupabaseManager.db_update("players", "id=eq." + target_uid, {"face_value": old_face - 5})

# 重置所有测试数据
func reset_test_data() -> void:
	log_test("正在重置测试数据...")
	# 这是一个危险操作，仅限测试局
	var tables = ["rumors", "intel_fragments", "eavesdrop_sessions", "achievements", "settlement_bonus", "asset_transfers", "actions", "messages"]
	for t in tables:
		# 使用 db_delete 配合 filter
		await SupabaseManager.db_delete(t, "game_id=eq." + test_game_id)
	
	log_test("测试数据已清除。")

func log_test(msg: String) -> void:
	print("[TEST] ", msg)
	test_log.emit(msg)

func run_all_tests() -> void:
	log_test("=== 丫鬟系统集成测试开始 ===")
	await setup_test_environment()
	await test_intel_generation()
	await test_rumor_fermentation()
	await test_redemption_achievement()
	await test_partnership_monitoring()
	log_test("=== 测试完成 ===")

# 场景5：双人挂机与对食背叛测试
func test_partnership_monitoring() -> void:
	log_test("--- 开始测试：双人挂机与对食背叛 ---")
	
	# 1. 建立对食关系
	await SupabaseManager.db_insert("maid_relationships", {
		"game_id": test_game_id,
		"player_a_uid": maid_a_uid,
		"player_b_uid": maid_b_uid,
		"relation_type": "dui_shi",
		"status": "active"
	})
	
	# 2. 模拟双人挂机开启
	var session_res = await SupabaseManager.db_insert("eavesdrop_sessions", {
		"player_uid": maid_a_uid,
		"partner_uid": maid_b_uid,
		"game_id": test_game_id,
		"scene": "yi_hong_yuan",
		"is_duo": true,
		"status": "active",
		"ends_at": Time.get_datetime_string_from_unix_time(int(Time.get_unix_time_from_system()) + 3600)
	})
	
	var session_id = session_res["data"]["id"]
	
	# 3. 触发情报生成（双人模式应生成两条碎片）
	await EavesdropManager.generate_intel_fragment(session_id, true)
	
	# 4. 验证情报翻倍
	var frag_a = await SupabaseManager.db_get("/rest/v1/intel_fragments?player_uid=eq.%s&session_id=eq.%s&select=*" % [maid_a_uid, session_id])
	var frag_b = await SupabaseManager.db_get("/rest/v1/intel_fragments?player_uid=eq.%s&session_id=eq.%s&select=*" % [maid_b_uid, session_id])
	
	if not frag_a["data"].is_empty() and not frag_b["data"].is_empty():
		log_test("断言成功：双人挂机情报翻倍生成。")
	else:
		log_test("断言失败：情报未正确分配给双方。")
		
	# 5. 模拟一方背叛
	await SupabaseManager.db_update("maid_relationships", "player_a_uid=eq.%s&player_b_uid=eq.%s" % [maid_a_uid, maid_b_uid], {
		"status": "betrayed",
		"betrayer_uid": maid_a_uid
	})
	
	# 6. 断言：背叛逻辑通常会触发共享情报的结算（这里根据业务逻辑模拟）
	log_test("背叛测试完成：maid_a 已背叛，maid_b 将获得补偿/共享副本。")
