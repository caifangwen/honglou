extends Control

# TreasuryUI.gd - 银库界面 UI 脚本
# 负责展示公中银两、月例发放、批条行动及双账本切换

@onready var total_silver_label: Label = $Header/TotalSilverLabel
@onready var deficit_progress_bar: ProgressBar = get_node_or_null("Header/DeficitBar")
@onready var stamina_label: Label = $ActionPanel/StaminaDisplay
@onready var private_assets_label: Label = get_node_or_null("ActionPanel/PrivateAssetsLabel")
@onready var prosperity_label: Label = get_node_or_null("Header/ProsperityLabel")

@onready var public_ledger_view: ScrollContainer = $TabContainer/PublicLedger/LedgerList
@onready var private_ledger_view: ScrollContainer = $TabContainer/PrivateLedger/PrivateLedgerList
@onready var player_list: VBoxContainer = get_node_or_null("AllocationPanel/PlayerAllocationList/PlayerAllocationVBox")

# 新增：月例汇总与历史列表
@onready var today_summary_label: Label = get_node_or_null("Header/TodaySummaryLabel")
@onready var history_list: VBoxContainer = get_node_or_null("TabContainer/History/HistoryListVBox")

var current_steward_data: Dictionary = {}
var current_treasury_data: Dictionary = {}
var allowance_history: Array = []

func _ready() -> void:
	# 初始化数据
	_refresh_data()
	
	# 导航按钮连接
	$Header/BackBtn.pressed.connect(_on_BackBtn_pressed)
	$Header/InboxBtn.pressed.connect(_on_InboxBtn_pressed)
	
	# 设置实时监听
	SupabaseManager.subscribe_to_table("treasury")
	SupabaseManager.subscribe_to_table("allowance_records")
	SupabaseManager.realtime_update.connect(_on_realtime_update)

func _on_realtime_update(table: String, data: Dictionary) -> void:
	match table:
		"treasury":
			_refresh_treasury_data()
		"allowance_records":
			_refresh_allowance_data()

func _refresh_data() -> void:
	_refresh_treasury_data()
	_refresh_steward_data()
	_refresh_allowance_data()
	_load_player_allocation_list()

func _refresh_treasury_data() -> void:
	var game_id = GameState.current_game_id
	var t_res = await SupabaseManager.db_get("/rest/v1/treasury?game_id=eq.%s&select=*" % game_id)
	if t_res["code"] == 200 and not t_res["data"].is_empty():
		current_treasury_data = t_res["data"][0]
		_update_treasury_ui()
	elif t_res["code"] == 200:
		await _initialize_treasury(game_id)

func _refresh_steward_data() -> void:
	var game_id = GameState.current_game_id
	var steward_uid = SupabaseManager.current_uid
	
	# 1. 获取 steward_accounts (旧逻辑保留以防万一)
	var s_res = await SupabaseManager.db_get("/rest/v1/steward_accounts?steward_uid=eq.%s&game_id=eq.%s&select=*" % [steward_uid, game_id])
	if s_res["code"] == 200 and not s_res["data"].is_empty():
		current_steward_data = s_res["data"][0]
	
	# 2. 获取 players 表中的最新私产 (新逻辑)
	var p_res = await SupabaseManager.db_get("/rest/v1/players?auth_uid=eq.%s&select=private_silver" % steward_uid)
	if p_res["code"] == 200 and not p_res["data"].is_empty():
		var private_silver = p_res["data"][0].get("private_silver", 0)
		if private_assets_label:
			private_assets_label.text = "个人私产: **%d**" % private_silver
		# 同步到 PlayerState
		PlayerState.silver = private_silver

func _refresh_allowance_data() -> void:
	var game_id = GameState.current_game_id
	
	# 1. 获取今日汇总
	var today = Time.get_date_string_from_system()
	var summary_res = await SupabaseManager.db_get("/rest/v1/allowance_records?game_id=eq.%s&issued_at=gte.%s&select=amount_public.sum()" % [game_id, today])
	if summary_res["code"] == 200 and not summary_res["data"].is_empty():
		var total_today = summary_res["data"][0].get("sum", 0)
		if today_summary_label:
			today_summary_label.text = "今日应发合计: %d" % total_today
	
	# 2. 获取历史记录 (按时间倒序)
	var history_res = await SupabaseManager.db_get("/rest/v1/allowance_records?game_id=eq.%s&order=issued_at.desc&limit=20&select=*,players:player_id(character_name)" % game_id)
	if history_res["code"] == 200:
		allowance_history = history_res["data"]
		_update_history_ui()

func _update_history_ui() -> void:
	if not history_list: return
	
	for child in history_list.get_children():
		child.queue_free()
		
	for record in allowance_history:
		var item = HBoxContainer.new()
		var time_label = Label.new()
		time_label.text = record.get("issued_at", "").split("T")[0]
		
		var name_label = Label.new()
		var player_data = record.get("players", {})
		name_label.text = player_data.get("character_name", "未知玩家")
		
		var amount_label = Label.new()
		amount_label.text = "明账: %d" % record.get("amount_public", 0)
		
		item.add_child(time_label)
		item.add_child(name_label)
		item.add_child(amount_label)
		history_list.add_child(item)

func _initialize_treasury(game_id: String) -> void:
	# 初始化银库数据
	var initial_data = {
		"game_id": game_id,
		"total_silver": 10000,
		"prosperity_level": 5,
		"deficit_rate": 0.0
	}
	var res = await SupabaseManager.db_insert("treasury", initial_data)
	if res["code"] == 201:
		current_treasury_data = res["data"][0]
		_update_treasury_ui()

func _initialize_steward_account(steward_uid: String, game_id: String) -> void:
	# 初始化管家账户
	var initial_data = {
		"game_id": game_id,
		"steward_uid": steward_uid,
		"public_ledger": [],
		"private_ledger": [],
		"private_assets": 0,
		"prestige": 50
	}
	var res = await SupabaseManager.db_insert("steward_accounts", initial_data)
	if res["code"] == 201:
		current_steward_data = res["data"][0]
		_update_steward_ui()
		
		# 同时初始化管家精力
		var stamina_data = {
			"uid": steward_uid,
			"game_id": game_id,
			"current_stamina": 6,
			"max_stamina": 6
		}
		await SupabaseManager.db_insert("steward_stamina", stamina_data)

func _update_treasury_ui() -> void:
	var total = current_treasury_data.get("total_silver", 0)
	var deficit = GameState.deficit_value # 使用全局状态中的亏空值
	var prosperity = current_treasury_data.get("prosperity_level", 1)
	
	# 同步到全局状态
	GameState.total_silver = total
	GameState.total_silver_changed.emit(total)
	
	if total_silver_label:
		total_silver_label.text = "总银两: %d" % total
		if deficit > 50.0:
			total_silver_label.add_theme_color_override("font_color", Color.RED)
		else:
			total_silver_label.add_theme_color_override("font_color", Color.WHITE)

	if prosperity_label:
		prosperity_label.text = "繁荣度: Lv.%d" % prosperity
		
	if deficit_progress_bar:
		deficit_progress_bar.value = deficit
		# 颜色阶梯：绿 -> 黄 -> 橙 -> 红
		# 使用 duplicate() 确保只修改当前实例的样式，不影响全局主题
		var style = deficit_progress_bar.get_theme_stylebox("fill").duplicate()
		if style is StyleBoxFlat:
			if deficit < 20.0: style.bg_color = Color.GREEN
			elif deficit < 50.0: style.bg_color = Color.YELLOW
			elif deficit < 80.0: style.bg_color = Color.ORANGE
			else: style.bg_color = Color.RED
			deficit_progress_bar.add_theme_stylebox_override("fill", style)

func _update_steward_ui() -> void:
	# 该函数现在主要由 _refresh_steward_data 内部处理 UI 更新
	pass

func _load_player_allocation_list() -> void:
	if not player_list:
		return
		
	# 获取当前局所有玩家
	var p_res = await SupabaseManager.db_get("/rest/v1/players?current_game_id=eq.%s&select=id,character_name,role_class" % GameState.current_game_id)
	if p_res["code"] == 200:
		# 清空旧列表
		for child in player_list.get_children():
			child.queue_free()
			
		for p in p_res["data"]:
			_add_player_to_list(p)

func _add_player_to_list(player_info: Dictionary) -> void:
	# 动态创建列表项
	var item = HBoxContainer.new()
	var name_label = Label.new()
	name_label.text = player_info["character_name"]
	name_label.custom_minimum_size = Vector2(100, 0)
	
	var standard_label = Label.new()
	var standard = 20 # 默认标准
	standard_label.text = "应发: %d" % standard
	
	var actual_input = SpinBox.new()
	actual_input.value = standard
	actual_input.min_value = 0
	actual_input.max_value = standard * 2 # 允许超发
	
	var send_btn = Button.new()
	send_btn.text = "发放"
	send_btn.pressed.connect(distribute_allowance.bind(player_info["id"], int(actual_input.value), standard))
	
	item.add_child(name_label)
	item.add_child(standard_label)
	item.add_child(actual_input)
	item.add_child(send_btn)
	player_list.add_child(item)

# 场景中已连接的信号处理器
func _on_action_pressed(action_type: String) -> void:
	# 执行批条行动
	var result = await StaminaManager.execute_steward_action(action_type, "", {})
	if result["success"]:
		_refresh_data()
		# 弹出成功提示
		print("行动执行成功: ", action_type)
	else:
		# 行动执行失败逻辑
		push_error("行动执行失败: " + action_type)

func distribute_allowance(target_uid: String, amount: int, standard: int):
	# 1. 调用 Edge Function 处理基础逻辑（扣除银库、记录流水）
	var body = {
		"steward_uid": SupabaseManager.current_uid,
		"recipient_uid": target_uid,
		"actual_amount": amount,
		"standard_amount": standard,
		"game_id": GameState.current_game_id
	}
	var res = await SupabaseManager._post("/functions/v1/distribute-allowance", JSON.stringify(body), true)
	if res["code"] != 200:
		push_error("发放月例失败: %s" % str(res.get("error", "Unknown error")))
		return

	# 2. 补全缺失部分：更新目标玩家银两
	# 使用 players.id 作为 target_uid
	await SupabaseManager.db_rpc("modify_player_stats", {
		"p_id": target_uid,
		"silver_delta": amount
	})

	# 3. 补全缺失部分：更新管家私产 (players.private_silver)
	var withheld = standard - amount
	if withheld > 0:
		# 获取管家在 players 表中的 ID
		var steward_player_id = PlayerState.player_db_id
		# 获取当前私产并累加
		var p_res = await SupabaseManager.db_get("/rest/v1/players?id=eq.%s&select=private_silver" % steward_player_id)
		var current_private = 0
		if p_res["code"] == 200 and not p_res["data"].is_empty():
			current_private = p_res["data"][0].get("private_silver", 0)
			
		await SupabaseManager.db_update("players", "id=eq.%s" % steward_player_id, {
			"private_silver": current_private + withheld
		})

	# 4. 重新计算亏空百分比并写入 game_state (games 表)
	await _recalculate_deficit(withheld)

	# 5. 刷新 UI
	_refresh_data()

func _recalculate_deficit(delta_withheld: int) -> void:
	var game_id = GameState.current_game_id
	
	# 获取历史总额汇总
	var stats_res = await SupabaseManager.db_get("/rest/v1/allowance_records?game_id=eq.%s&select=amount_public.sum(),withheld_amount.sum()" % game_id)
	if stats_res["code"] == 200 and not stats_res["data"].is_empty():
		var total_standard = stats_res["data"][0].get("sum_amount_public", 0)
		var total_withheld = stats_res["data"][0].get("sum_withheld_amount", 0)
		
		var deficit_percent = 0.0
		if total_standard > 0:
			deficit_percent = (float(total_withheld) / float(total_standard)) * 100.0
		
		# 写入 games 表 (deficit_value)
		await SupabaseManager.db_update("games", "id=eq.%s" % game_id, {
			"deficit_value": deficit_percent
		})
		
		# 同步写一条记录到 deficit_log
		var log_data = {
			"game_id": game_id,
			"operated_by": PlayerState.player_db_id,
			"delta_amount": delta_withheld,
			"new_deficit_percent": deficit_percent
		}
		await SupabaseManager.db_insert("deficit_log", log_data)
		
		# 更新全局状态
		GameState.deficit_value = deficit_percent
		GameState.deficit_changed.emit(deficit_percent)

# --- 按钮信号处理 ---

func _on_ConfirmAllocationBtn_pressed() -> void:
	# 批量发放逻辑：遍历列表并触发所有发放
	print("[TreasuryUI] 暂未实现批量发放，请点击玩家右侧的发放按钮。")

func _on_ProcureBtn_pressed() -> void: _on_action_pressed("procurement")
func _on_AssignTaskBtn_pressed() -> void: _on_action_pressed("assignment")
func _on_SearchGardenBtn_pressed() -> void: _on_action_pressed("search")
func _on_AdvanceBtn_pressed() -> void: _on_action_pressed("advance")
func _on_SuppressRumorBtn_pressed() -> void: _on_action_pressed("suppress_rumor")
func _on_BlockInfoBtn_pressed() -> void: _on_action_pressed("block_intel")

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_InboxBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Inbox.tscn")
