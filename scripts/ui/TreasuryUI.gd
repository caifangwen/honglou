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

var current_steward_data: Dictionary = {}
var current_treasury_data: Dictionary = {}

func _ready() -> void:
	# 初始化数据
	_refresh_data()
	
	# 设置实时监听 (Supabase Realtime 示例逻辑)
	# SupabaseManager.subscribe_to_table("treasury", _on_treasury_updated)

func _refresh_data() -> void:
	# 获取银库状态
	var game_id = GameState.current_game_id
	var steward_uid = SupabaseManager.current_uid
	
	if game_id == "" or steward_uid == "":
		push_error("[TreasuryUI] 游戏ID或用户ID为空")
		return

	# 1. 获取银库
	var t_res = await SupabaseManager.db_get("/rest/v1/treasury?game_id=eq.%s&select=*" % game_id)
	if t_res["code"] == 200:
		if t_res["data"].is_empty():
			# 如果银库不存在，尝试初始化一条（仅限测试环境或管家首次进入）
			await _initialize_treasury(game_id)
		else:
			current_treasury_data = t_res["data"][0]
			_update_treasury_ui()
	
	# 2. 获取管家账户（私产、账本）
	var s_res = await SupabaseManager.db_get("/rest/v1/steward_accounts?steward_uid=eq.%s&game_id=eq.%s&select=*" % [steward_uid, game_id])
	if s_res["code"] == 200:
		if s_res["data"].is_empty():
			await _initialize_steward_account(steward_uid, game_id)
		else:
			current_steward_data = s_res["data"][0]
			_update_steward_ui()
	
	# 3. 获取精力
	var stamina = await StaminaManager.get_current_stamina(steward_uid)
	if stamina_label:
		stamina_label.text = "精力: %d / 6" % stamina
	
	# 4. 获取待发放月例玩家列表
	_load_player_allocation_list()

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

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _update_treasury_ui() -> void:
	var total = current_treasury_data.get("total_silver", 0)
	var deficit = current_treasury_data.get("deficit_rate", 0.0)
	var prosperity = current_treasury_data.get("prosperity_level", 1)
	
	if total_silver_label:
		total_silver_label.text = "总银两: %d" % total
		if deficit > 0.5:
			total_silver_label.add_theme_color_override("font_color", Color.RED)
		else:
			total_silver_label.add_theme_color_override("font_color", Color.WHITE)

	if prosperity_label:
		prosperity_label.text = "繁荣度: Lv.%d" % prosperity
		
	if deficit_progress_bar:
		deficit_progress_bar.value = deficit * 100
		# 颜色阶梯：绿 -> 黄 -> 橙 -> 红
		var style = deficit_progress_bar.get_theme_stylebox("fill")
		if style is StyleBoxFlat:
			if deficit < 0.2: style.bg_color = Color.GREEN
			elif deficit < 0.5: style.bg_color = Color.YELLOW
			elif deficit < 0.8: style.bg_color = Color.ORANGE
			else: style.bg_color = Color.RED

func _update_steward_ui() -> void:
	# 优先使用 PlayerState.silver (已从 steward_accounts 同步)
	var private_assets = PlayerState.silver if PlayerState.role_class == "steward" else current_steward_data.get("private_assets", 0)
	if private_assets_label:
		# 简单的混淆显示 (例如：**123**)
		private_assets_label.text = "个人私产: **%d**" % private_assets

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
		# 弹出错误提示
		push_error("行动执行失败: " + result["error"])

# 月例发放逻辑
func distribute_allowance(target_uid: String, amount: int, standard: int):
	var body = {
		"steward_uid": SupabaseManager.current_uid,
		"recipient_uid": target_uid,
		"actual_amount": amount,
		"standard_amount": standard,
		"game_id": GameState.current_game_id
	}
	SupabaseManager._post("/functions/v1/distribute-allowance", JSON.stringify(body), true)
	var res = await SupabaseManager.request_completed
	if res["code"] == 200:
		_refresh_data()
	else:
		push_error("发放月例失败")
