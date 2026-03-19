extends Control

# TreasuryUI.gd - 银库界面 UI 脚本
# 负责展示公中银两、月例发放、批条行动及双账本切换

@onready var total_silver_label: Label = $Header/TotalSilverLabel
@onready var deficit_progress_bar: ProgressBar = get_node_or_null("Header/DeficitBar")
@onready var stamina_label: Label = $ActionPanel/StaminaDisplay
@onready var private_assets_label: Label = get_node_or_null("ActionPanel/PrivateAssetsLabel")
@onready var prosperity_label: Label = get_node_or_null("Header/ProsperityLabel")
@onready var debug_allowance_btn: Button = get_node_or_null("ActionPanel/DebugAllowanceBtn")

@onready var public_ledger_view: VBoxContainer = get_node_or_null("TabContainer/PublicLedger/LedgerList/LedgerVBox")
@onready var private_ledger_view: VBoxContainer = get_node_or_null("TabContainer/PrivateLedger/PrivateLedgerList/PrivateLedgerVBox")
@onready var player_list: VBoxContainer = get_node_or_null("AllocationPanel/PlayerAllocationList/PlayerAllocationVBox")

# 新增：月例汇总与历史列表
@onready var today_summary_label: Label = get_node_or_null("Header/TodaySummaryLabel")
@onready var history_list: VBoxContainer = get_node_or_null("TabContainer/History/HistoryListVBox")
@onready var account_popup: Control = get_node_or_null("AccountPopup")
@onready var account_popup_content: ScrollContainer = get_node_or_null("AccountPopup/VBoxContainer/Content")
@onready var account_popup_close_btn: Button = get_node_or_null("AccountPopup/VBoxContainer/CloseBtn")

# 差事分派相关节点
@onready var assign_task_panel: PanelContainer = get_node_or_null("AssignTaskPanel")
@onready var task_type_selector: OptionButton = get_node_or_null("AssignTaskPanel/TaskTypeSelector")
@onready var task_target_selector: OptionButton = get_node_or_null("AssignTaskPanel/TaskTargetSelector")
@onready var task_reward_input: SpinBox = get_node_or_null("AssignTaskPanel/RewardInput")
@onready var task_confirm_btn: Button = get_node_or_null("AssignTaskPanel/ConfirmBtn")
@onready var task_cancel_btn: Button = get_node_or_null("AssignTaskPanel/CancelBtn")

# 调试标签
@onready var debug_count_label: Label = get_node_or_null("TabContainer/PublicLedger/DebugCountLabel")

var current_steward_data: Dictionary = {}
var current_treasury_data: Dictionary = {}
var allowance_history: Array = []

# 差事类型定义
const TASK_TYPES = {
	"errand": { "name": "跑腿差事", "base_cost": 1, "base_reward": 5, "stamina_drain": 2 },
	"guard": { "name": "看守差事", "base_cost": 1, "base_reward": 8, "stamina_drain": 1 },
	"purchase": { "name": "采办差事", "base_cost": 1, "base_reward": 10, "stamina_drain": 3 },
	"message": { "name": "传话差事", "base_cost": 1, "base_reward": 6, "stamina_drain": 2 },
	"clean": { "name": "打扫差事", "base_cost": 1, "base_reward": 4, "stamina_drain": 2 },
	"special": { "name": "特殊差事", "base_cost": 2, "base_reward": 15, "stamina_drain": 4 }
}

var selected_task_type: String = "errand"
var selected_target_uid: String = ""

# 各项行动精力消耗（统一引用 GameConfig 常量）
const COST_STAMINA_PROCUREMENT: int = GameConfig.COST_PROCURE
const COST_STAMINA_ASSIGNMENT: int = GameConfig.COST_ASSIGN_TASK
const COST_STAMINA_SEARCH: int = GameConfig.COST_SEARCH_GARDEN
const COST_STAMINA_ADVANCE: int = GameConfig.COST_ADVANCE_PAYMENT
const COST_STAMINA_SUPPRESS: int = GameConfig.COST_SUPPRESS_RUMOR
const COST_STAMINA_BLOCK: int = GameConfig.COST_BLOCK_INFO
const COST_STAMINA_ALLOWANCE: int = 0 # 发放月例暂不消耗精力

func _ready() -> void:
	# 初始化数据
	_refresh_data()

	# 导航按钮连接
	$Header/BackBtn.pressed.connect(_on_BackBtn_pressed)
	$Header/InboxBtn.pressed.connect(_on_InboxBtn_pressed)

	if debug_allowance_btn:
		debug_allowance_btn.pressed.connect(_on_DebugAllowanceBtn_pressed)

	# 确保行动按钮已连接 (防止 .tscn 中连接丢失)
	_connect_action_buttons()

	# 账目弹窗关闭按钮连接
	if account_popup_close_btn:
		account_popup_close_btn.pressed.connect(_on_account_popup_close)

	# 差事分派面板连接
	_connect_task_panel()

	# 设置实时监听
	SupabaseManager.subscribe_to_table("treasury")
	SupabaseManager.subscribe_to_table("allowance_records")
	SupabaseManager.subscribe_to_table("steward_accounts")
	SupabaseManager.subscribe_to_table("players") # 监听玩家属性变化
	SupabaseManager.realtime_update.connect(_on_realtime_update)

func _on_realtime_update(table: String, data: Dictionary) -> void:
	match table:
		"treasury":
			_refresh_treasury_data()
		"allowance_records":
			_refresh_allowance_data()
		"steward_accounts":
			_refresh_steward_data()
		"players":
			# 如果是管家本人的数据变化，刷新管家 UI
			if data.get("id") == PlayerState.player_db_id:
				_refresh_steward_data()

func _refresh_data() -> void:
	_refresh_treasury_data()
	_refresh_steward_data()
	_refresh_allowance_data()
	_load_player_allocation_list()

func _connect_action_buttons() -> void:
	# 显式连接行动面板中的按钮
	var proc_btn = get_node_or_null("ActionPanel/ProcureBtn")
	if proc_btn and not proc_btn.pressed.is_connected(_on_ProcureBtn_pressed):
		proc_btn.pressed.connect(_on_ProcureBtn_pressed)

	var assign_btn = get_node_or_null("ActionPanel/AssignTaskBtn")
	if assign_btn and not assign_btn.pressed.is_connected(_on_AssignTaskBtn_pressed):
		assign_btn.pressed.connect(_on_AssignTaskBtn_pressed)

	var search_btn = get_node_or_null("ActionPanel/SearchGardenBtn")
	if search_btn and not search_btn.pressed.is_connected(_on_SearchGardenBtn_pressed):
		search_btn.pressed.connect(_on_SearchGardenBtn_pressed)

	var advance_btn = get_node_or_null("ActionPanel/AdvanceBtn")
	if advance_btn and not advance_btn.pressed.is_connected(_on_AdvanceBtn_pressed):
		advance_btn.pressed.connect(_on_AdvanceBtn_pressed)

	var suppress_btn = get_node_or_null("ActionPanel/SuppressRumorBtn")
	if suppress_btn and not suppress_btn.pressed.is_connected(_on_SuppressRumorBtn_pressed):
		suppress_btn.pressed.connect(_on_SuppressRumorBtn_pressed)

	var block_btn = get_node_or_null("ActionPanel/BlockInfoBtn")
	if block_btn and not block_btn.pressed.is_connected(_on_BlockInfoBtn_pressed):
		block_btn.pressed.connect(_on_BlockInfoBtn_pressed)

	var confirm_btn = get_node_or_null("AllocationPanel/ConfirmAllocationBtn")
	if confirm_btn and not confirm_btn.pressed.is_connected(_on_ConfirmAllocationBtn_pressed):
		confirm_btn.pressed.connect(_on_ConfirmAllocationBtn_pressed)

# 连接差事分派面板信号
func _connect_task_panel() -> void:
	if task_type_selector:
		task_type_selector.item_selected.connect(_on_task_type_selected)
	if task_target_selector:
		task_target_selector.item_selected.connect(_on_task_target_selected)
	if task_confirm_btn:
		task_confirm_btn.pressed.connect(_on_task_confirm_pressed)
	if task_cancel_btn:
		task_cancel_btn.pressed.connect(_on_task_cancel_pressed)

# 更新差事分派面板 UI
func _update_task_panel_ui() -> void:
	if not task_type_selector or not task_target_selector:
		return
	
	# 填充差事类型选项
	task_type_selector.clear()
	for key in TASK_TYPES.keys():
		var task_info = TASK_TYPES[key]
		var display_text = "%s (精力消耗：%d, 基础赏银：%d)" % [task_info.name, task_info.base_cost, task_info.base_reward]
		task_type_selector.add_item(display_text)
		task_type_selector.set_item_id(task_type_selector.get_item_count() - 1, key)
	
	# 填充目标玩家选项
	task_target_selector.clear()
	task_target_selector.add_item("—— 请选择目标 ——")
	if player_list:
		for item in player_list.get_children():
			if item.has_meta("player_id"):
				var player_id = item.get_meta("player_id")
				var character_name = item.get_meta("character_name")
				var role_class = item.get_meta("role_class", "servant")
				task_target_selector.add_item("%s (%s)" % [character_name, _get_role_display(role_class)])
				task_target_selector.set_item_id(task_target_selector.get_item_count() - 1, player_id)
	
	# 根据选择的差事类型更新赏银输入
	_update_reward_input()

func _get_role_display(role: String) -> String:
	match role:
		"master": return "主子"
		"servant": return "丫鬟/小厮"
		"elder": return "长辈"
		"guest": return "客人"
		_: return "管家"

func _update_reward_input() -> void:
	if not task_reward_input or selected_task_type == "":
		return
	
	var task_info = TASK_TYPES.get(selected_task_type, TASK_TYPES["errand"])
	task_reward_input.min_value = task_info.base_reward
	task_reward_input.max_value = task_info.base_reward * 3
	task_reward_input.value = task_info.base_reward
	task_reward_input.step = 1

func _on_task_type_selected(index: int) -> void:
	var task_id = task_type_selector.get_item_id(index)
	selected_task_type = str(task_id)
	_update_reward_input()

func _on_task_target_selected(index: int) -> void:
	if index == 0:
		selected_target_uid = ""
	else:
		var target_id = task_target_selector.get_item_id(index)
		selected_target_uid = str(target_id)

func _on_task_confirm_pressed() -> void:
	if selected_target_uid == "":
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "请选择目标玩家")
		return
	
	if selected_task_type == "":
		selected_task_type = "errand"
	
	var task_info = TASK_TYPES.get(selected_task_type, TASK_TYPES["errand"])
	var silver_reward = int(task_reward_input.value) if task_reward_input else task_info.base_reward
	
	# 执行差事分派
	_execute_assign_task(selected_target_uid, silver_reward, selected_task_type)

func _on_task_cancel_pressed() -> void:
	# 关闭差事分派面板
	if assign_task_panel:
		assign_task_panel.visible = false
	# 重置选择
	selected_task_type = "errand"
	selected_target_uid = ""

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

	if steward_uid == "":
		push_error("[TreasuryUI] Supabase current_uid is empty")
		return

	# 1. 获取 players 表中的最新属性
	var p_res = await SupabaseManager.db_get("/rest/v1/players?auth_uid=eq.%s&select=*" % steward_uid)
	if p_res["code"] == 200 and not p_res["data"].is_empty():
		var p_data = p_res["data"][0]
		
		# 使用 PlayerState 统一加载
		PlayerState.load_from_db(p_data)

		var private_silver = PlayerState.silver
		var current_stamina = PlayerState.get_current_stamina()
		var max_stamina = PlayerState.stamina_max
		var p_db_id = PlayerState.player_db_id

		if private_assets_label:
			private_assets_label.text = "个人私产: %d" % private_silver
		if stamina_label:
			stamina_label.text = "精力: %d/%d" % [current_stamina, max_stamina]

		# 2. 获取管家账本数据 (steward_accounts 表)
		if p_db_id != "":
			print("[TreasuryUI] 查询管家账本 - steward_uid: ", p_db_id, ", game_id: ", game_id)
			var s_res = await SupabaseManager.db_get("/rest/v1/steward_accounts?steward_uid=eq.%s&game_id=eq.%s&select=*" % [p_db_id, game_id])
			print("[TreasuryUI] 管家账本查询结果 - code: ", s_res["code"], ", data count: ", s_res["data"].size())
			if s_res["code"] == 200 and not s_res["data"].is_empty():
				current_steward_data = s_res["data"][0]
				print("[TreasuryUI] current_steward_data: ", str(current_steward_data).substr(0, 500))
				var public_ledger = current_steward_data.get("public_ledger", [])
				var private_ledger = current_steward_data.get("private_ledger", [])
				print("[TreasuryUI] 刷新账本数据 - 明账记录数: %d, 暗账记录数: %d" % [public_ledger.size(), private_ledger.size()])
				if not public_ledger.is_empty():
					print("[TreasuryUI] 最新明账记录：", str(public_ledger[-1]))
				if not private_ledger.is_empty():
					print("[TreasuryUI] 最新暗账记录：", str(private_ledger[-1]))
				_update_ledger_ui()
			elif s_res["code"] == 200:
				# 如果没有，则初始化
				print("[TreasuryUI] No steward account found for player ", p_db_id, ", initializing...")
				await _initialize_steward_account(p_db_id, game_id)
	else:
		push_error("[TreasuryUI] Failed to get player data: " + str(p_res.get("error", "Empty data")))

func _update_ledger_ui() -> void:
	print("[TreasuryUI] _update_ledger_ui 被调用")
	print("[TreasuryUI] public_ledger_view 存在：", public_ledger_view != null)
	print("[TreasuryUI] private_ledger_view 存在：", private_ledger_view != null)

	# 获取 TabContainer 引用
	var tab_container = get_node_or_null("TabContainer")
	
	# 更新明账
	if public_ledger_view:
		for child in public_ledger_view.get_children():
			child.queue_free()

		var public_ledger = current_steward_data.get("public_ledger", [])
		print("[TreasuryUI] 明账记录数：%d" % public_ledger.size())
		for entry in public_ledger:
			var label = Label.new()
			var time = entry.get("timestamp", "").split("T")[0]
			var amount = entry.get("amount", 0)
			var recipient = entry.get("recipient_name", "未知")
			var type = "发放" if entry.get("type") == "allowance" else "其他"
			label.text = "[%s] 给 %s %s: %d 两" % [time, recipient, type, amount]
			label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
			print("[TreasuryUI] 添加明账记录：", label.text)
			public_ledger_view.add_child(label)

		print("[TreasuryUI] 明账更新完成，子节点数：", public_ledger_view.get_child_count())
		
		# 更新调试标签
		if debug_count_label:
			debug_count_label.text = "记录数：%d" % public_ledger.size()

	# 更新暗账
	if private_ledger_view:
		for child in private_ledger_view.get_children():
			child.queue_free()

		var private_ledger = current_steward_data.get("private_ledger", [])
		print("[TreasuryUI] 暗账记录数：%d" % private_ledger.size())
		for entry in private_ledger:
			var label = Label.new()
			var time = entry.get("timestamp", "").split("T")[0]
			var withheld = entry.get("withheld", 0)
			var recipient = entry.get("recipient_name", "未知")
			var type = "克扣" if entry.get("type") == "embezzlement" else "其他"
			label.text = "[%s] 从 %s %s: %d 两" % [time, recipient, type, withheld]
			label.add_theme_color_override("font_color", Color.ORANGE)
			label.set_h_size_flags(Control.SIZE_EXPAND_FILL)
			print("[TreasuryUI] 添加暗账记录：", label.text)
			private_ledger_view.add_child(label)

		print("[TreasuryUI] 暗账更新完成，子节点数：", private_ledger_view.get_child_count())
	
	# 刷新 TabContainer 显示
	if tab_container:
		# 强制刷新标签页内容（使用 deferred 确保在帧更新后执行）
		tab_container.call_deferred("set_current_tab", 0)
		print("[TreasuryUI] 切换到第 0 个标签页 (明账)")
		# 确保 ScrollContainer 可见并刷新
		var public_ledger_list = get_node_or_null("TabContainer/PublicLedger/LedgerList")
		if public_ledger_list:
			public_ledger_list.visible = true
			public_ledger_list.queue_sort()
		
		# 强制重绘
		tab_container.queue_redraw()

func _refresh_allowance_data() -> void:
	var game_id = GameState.current_game_id
	
	# 1. 获取今日预计发放合计 (所有玩家的 standard_allowance 之和)
	# 如果数据库没有这个字段，我们先用固定值 1000 演示，或者计算 players 数量 * 20
	var p_res = await SupabaseManager.db_get("/rest/v1/players?current_game_id=eq.%s&select=id" % game_id)
	var total_expected = 1000 # 默认值
	if p_res["code"] == 200:
		total_expected = p_res["data"].size() * 20 # 假设每人 20
		
	if today_summary_label:
		today_summary_label.text = "今日应发合计: %d" % total_expected
	
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

# 显示本次发放的账目信息
func show_account_summary(distributions: Array, total_withheld: int) -> void:
	if not account_popup or not account_popup_content:
		push_error("[TreasuryUI] Account popup nodes not found, showing fallback message")
		print("[账目信息] 发放人数：%d, 克扣总额：%d 两" % [distributions.size(), total_withheld])
		return

	# 获取 ScrollContainer 内部的 VBoxContainer
	var content_vbox: VBoxContainer = account_popup_content.get_child(0) as VBoxContainer
	if not content_vbox:
		push_error("[TreasuryUI] Content VBoxContainer not found inside ScrollContainer")
		return

	# 清空旧内容
	for child in content_vbox.get_children():
		child.queue_free()

	# 添加标题
	var title_label = Label.new()
	title_label.text = "本次发放账目"
	title_label.add_theme_font_size_override("font_size", 18)
	content_vbox.add_child(title_label)

	var separator = HSeparator.new()
	content_vbox.add_child(separator)

	# 添加明细
	var total_standard = 0
	var total_actual = 0
	for dist in distributions:
		var item = VBoxContainer.new()
		item.add_theme_constant_override("separation", 2)

		var name_label = Label.new()
		name_label.text = "领用人：%s" % dist.get("recipient_name", "未知")
		name_label.add_theme_font_size_override("font_size", 14)
		item.add_child(name_label)

		var standard_label = Label.new()
		var standard = dist.get("standard_amount", 0)
		standard_label.text = "应发：%d 两" % standard
		item.add_child(standard_label)

		var actual_label = Label.new()
		var actual = dist.get("actual_amount", 0)
		actual_label.text = "实发：%d 两" % actual
		item.add_child(actual_label)

		var withheld = standard - actual
		if withheld > 0:
			var withheld_label = Label.new()
			withheld_label.text = "克扣：%d 两" % withheld
			withheld_label.add_theme_color_override("font_color", Color.ORANGE)
			item.add_child(withheld_label)

		total_standard += standard
		total_actual += actual

		content_vbox.add_child(item)
		var space = Control.new()
		space.custom_minimum_size = Vector2(0, 10)
		content_vbox.add_child(space)

	# 添加合计
	var total_separator = HSeparator.new()
	content_vbox.add_child(total_separator)

	var summary_label = Label.new()
	summary_label.text = "应发总计：%d 两" % total_standard
	summary_label.add_theme_font_size_override("font_size", 16)
	content_vbox.add_child(summary_label)

	var actual_summary_label = Label.new()
	actual_summary_label.text = "实发总计：%d 两" % total_actual
	actual_summary_label.add_theme_font_size_override("font_size", 16)
	content_vbox.add_child(actual_summary_label)

	var withheld_summary_label = Label.new()
	withheld_summary_label.text = "克扣总额：%d 两" % total_withheld
	withheld_summary_label.add_theme_font_size_override("font_size", 16)
	withheld_summary_label.add_theme_color_override("font_color", Color.ORANGE)
	content_vbox.add_child(withheld_summary_label)

	# 显示弹窗
	account_popup.visible = true

# 关闭账目信息弹窗
func _on_account_popup_close() -> void:
	if account_popup:
		account_popup.visible = false

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
		_update_ledger_ui()
		print("[TreasuryUI] Steward account initialized successfully")
	else:
		push_error("[TreasuryUI] Failed to initialize steward account: " + str(res.get("error", "Unknown error")))

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

	var game_id = GameState.current_game_id
	print("[TreasuryUI] Loading player list for game_id: ", game_id)

	# 获取当前局所有玩家
	var p_res = await SupabaseManager.db_get("/rest/v1/players?current_game_id=eq.%s&select=id,character_name,role_class" % game_id)
	if p_res["code"] == 200:
		# 清空旧列表
		for child in player_list.get_children():
			child.queue_free()

		if p_res["data"].is_empty():
			# 调试：如果没有玩家，尝试不带过滤获取 (仅限测试)
			print("[TreasuryUI] No players found for this game, trying fallback...")
			var p_res_all = await SupabaseManager.db_get("/rest/v1/players?limit=10&select=id,character_name,role_class")
			if p_res_all["code"] == 200:
				for p in p_res_all["data"]:
					_add_player_to_list(p)
		else:
			for p in p_res["data"]:
				_add_player_to_list(p)
		
		# 刷新差事分派面板的目标选择器
		_update_task_panel_ui()
	else:
		push_error("[TreasuryUI] Failed to load players: " + str(p_res.get("error", "Unknown error")))

func _add_player_to_list(player_info: Dictionary) -> void:
	# 动态创建列表项
	var item = HBoxContainer.new()
	item.set_meta("player_id", player_info.get("id", ""))
	item.set_meta("character_name", player_info.get("character_name", "未知"))
	
	var name_label = Label.new()
	name_label.text = player_info.get("character_name", "未知")
	name_label.custom_minimum_size = Vector2(100, 0)
	
	var standard_label = Label.new()
	var standard = 20 # 默认标准
	standard_label.text = "应发: %d" % standard
	item.set_meta("standard_amount", standard)
	
	var actual_input = SpinBox.new()
	actual_input.name = "ActualInput"
	actual_input.value = standard
	actual_input.min_value = 0
	actual_input.max_value = standard * 2 # 允许超发
	
	var send_btn = Button.new()
	send_btn.text = "发放"
	send_btn.pressed.connect(func(): distribute_allowance(player_info["id"], int(actual_input.value), standard))
	
	item.add_child(name_label)
	item.add_child(standard_label)
	item.add_child(actual_input)
	item.add_child(send_btn)
	player_list.add_child(item)

func _execute_batch_action(action_type: String, extra: Dictionary = {}) -> void:
	var rpc_name := ""
	var params: Dictionary = {}
	var cost: int = 0
	
	match action_type:
		"procurement":
			rpc_name = "steward_procure_goods"
			cost = COST_STAMINA_PROCUREMENT
			params = {
				"p_item_template_key": extra.get("item_template_key", "generic_supply"),
				"p_quantity": extra.get("quantity", 1)
			}
		"assignment":
			rpc_name = "steward_assign_task"
			cost = COST_STAMINA_ASSIGNMENT
			var target_uid: String = extra.get("target_uid", "")
			if target_uid == "":
				push_error("请先选择一名目标玩家再派差事")
				return
			params = {
				"p_target_uid": target_uid,
				"p_silver_reward": extra.get("silver_reward", 10)
			}
		"search":
			rpc_name = "steward_search_players"
			cost = COST_STAMINA_SEARCH
			params = {}
		"advance":
			rpc_name = "steward_advance_credit"
			cost = COST_STAMINA_ADVANCE
			var adv_target: String = extra.get("target_uid", "")
			if adv_target == "":
				push_error("请先选择一名目标玩家再预支批条")
				return
			params = {
				"p_target_uid": adv_target,
				"p_amount": extra.get("amount", 20),
				"p_deficit_step": extra.get("deficit_step", 5)
			}
		"suppress_rumor":
			rpc_name = "steward_suppress_rumor"
			cost = COST_STAMINA_SUPPRESS
			var rumor_id: String = extra.get("rumor_id", "")
			if rumor_id == "":
				push_error("未指定要平息的流言")
				return
			params = {"p_rumor_id": rumor_id}
		"block_intel":
			rpc_name = "steward_block_intel"
			cost = COST_STAMINA_BLOCK
			var intel_id: String = extra.get("intel_id", "")
			if intel_id == "":
				push_error("未指定要封锁的情报")
				return
			params = {"p_intel_id": intel_id}
		_:
			push_error("未知行动类型: " + action_type)
			return
	
	# 检查精力是否足够
	if PlayerState.get_current_stamina() < cost:
		push_error("精力不足，执行该行动需要 %d 点精力" % cost)
		return
	
	var res = await SupabaseManager.db_rpc(rpc_name, params)
	var ok: bool = int(res.get("code", 0)) == 200
	if ok:
		var data = res.get("data")
		if data is Dictionary and data.has("success") and data["success"] == false:
			ok = false
	
	if ok:
		# 行动执行成功后，手动扣除精力以更新 UI
		if cost > 0:
			PlayerState.consume_stamina(cost)
		_refresh_data()
		print("行动执行成功: ", action_type)
		# 可以在此处通过 EventBus 发送成功通知
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "【银库】行动执行成功！")
	else:
		var err = str(res.get("error", res.get("data", {}).get("error", "未知错误")))
		push_error("行动执行失败: %s" % err)
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "【银库】行动失败: %s" % err)

func distribute_allowance(target_uid: String, amount: int, standard: int):
	print("[TreasuryUI] Attempting to distribute allowance: target=%s, amount=%d" % [target_uid, amount])
	
	# 确保我们有 steward_id
	var steward_id = PlayerState.player_db_id
	if steward_id == "":
		# 尝试从 PlayerState 或数据库重新获取
		var s_uid = SupabaseManager.current_uid
		var p_res = await SupabaseManager.db_get("/rest/v1/players?auth_uid=eq.%s&select=id" % s_uid)
		if p_res["code"] == 200 and not p_res["data"].is_empty():
			steward_id = p_res["data"][0]["id"]
			PlayerState.player_db_id = steward_id
		else:
			var err_msg = "无法获取管家玩家ID，发放失败"
			push_error(err_msg)
			# 如果有提示框组件可以调用，这里先用打印
			print(err_msg)
			return

	# 获取目标玩家姓名
	var target_name = "未知"
	if player_list:
		for item in player_list.get_children():
			if item.has_meta("player_id") and item.get_meta("player_id") == target_uid:
				target_name = item.get_meta("character_name")
				break

	# 1. 调用 RPC 处理基础逻辑
	print("[TreasuryUI] Invoking distribute-allowance rpc...")
	var params = {
		"p_steward_uid": steward_id,
		"p_recipient_uid": target_uid,
		"p_recipient_name": target_name,
		"p_actual_amount": amount,
		"p_standard_amount": standard,
		"p_game_id": GameState.current_game_id
	}
	var res = await SupabaseManager.db_rpc("distribute_allowance_rpc", params)
	
	if res["code"] != 200 or (res.has("data") and res["data"] is Dictionary and res["data"].get("success") == false):
		var err = str(res.get("error", res.get("data", {}).get("error", "Unknown error")))
		push_error("发放月例失败: %s" % err)
		print("发放月例失败: ", err)
		return

	print("[TreasuryUI] Distribution successful, recalculating deficit...")
	# 2. 重新计算亏空百分比并写入 game_state (games 表)
	var withheld = standard - amount
	await _recalculate_deficit(withheld)

	# 3. 刷新 UI 前，先直接查询数据库验证
	print("[TreasuryUI] 发放成功，直接查询数据库验证...")
	var verify_res = await SupabaseManager.db_get("/rest/v1/steward_accounts?steward_uid=eq.%s&game_id=eq.%s&select=*" % [PlayerState.player_db_id, GameState.current_game_id])
	print("[TreasuryUI] 验证查询结果 - data count: ", verify_res["data"].size())
	if verify_res["data"].size() > 0:
		var ledger_data = verify_res["data"][0]
		print("[TreasuryUI] 验证 - 明账记录数：", (ledger_data.get("public_ledger", []) as Array).size())
		print("[TreasuryUI] 验证 - 暗账记录数：", (ledger_data.get("private_ledger", []) as Array).size())

	# 3. 刷新 UI
	_refresh_data()
	print("[TreasuryUI] Data refreshed")

	# 4. 显示账目信息弹窗
	var distributions = [{
		"recipient_uid": target_uid,
		"recipient_name": target_name,
		"standard_amount": standard,
		"actual_amount": amount
	}]
	show_account_summary(distributions, withheld)

func _recalculate_deficit(delta_withheld: int) -> void:
	var game_id = GameState.current_game_id
	
	# 获取历史总额汇总 (使用新 RPC)
	var stats_res = await SupabaseManager.db_rpc("get_treasury_stats", {"p_game_id": game_id})
	if stats_res["code"] == 200 and not stats_res["data"].is_empty():
		var stats = stats_res["data"][0]
		var total_standard = stats.get("sum_public", 0)
		var total_withheld = stats.get("sum_withheld", 0)
		
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
	if not player_list or player_list.get_child_count() == 0:
		print("[TreasuryUI] 列表为空，无需发放")
		return
		
	var steward_id = PlayerState.player_db_id
	if steward_id == "":
		var s_uid = SupabaseManager.current_uid
		var p_res = await SupabaseManager.db_get("/rest/v1/players?auth_uid=eq.%s&select=id" % s_uid)
		if p_res["code"] == 200 and not p_res["data"].is_empty():
			steward_id = p_res["data"][0]["id"]
			PlayerState.player_db_id = steward_id
		else:
			push_error("无法获取管家玩家ID，发放失败")
			return

	var distributions = []
	var total_withheld = 0
	
	for item in player_list.get_children():
		if not item.has_meta("player_id"): continue
		
		var player_id = item.get_meta("player_id")
		var character_name = item.get_meta("character_name")
		var standard = item.get_meta("standard_amount")
		var actual_input = item.get_node_or_null("ActualInput")
		if not actual_input: continue
		
		var actual = int(actual_input.value)
		distributions.append({
			"recipient_uid": player_id,
			"recipient_name": character_name,
			"actual_amount": actual,
			"standard_amount": standard
		})
		total_withheld += (standard - actual)
		
	if distributions.is_empty():
		print("[TreasuryUI] 没有可发放的数据")
		return
		
	print("[TreasuryUI] 开始批量发放，人数: ", distributions.size())
	
	var params = {
		"p_steward_uid": steward_id,
		"p_game_id": GameState.current_game_id,
		"p_distributions": distributions
	}
	
	var res = await SupabaseManager.db_rpc("bulk_distribute_allowance_rpc", params)
	if res["code"] != 200 or (res.has("data") and res["data"] is Dictionary and res["data"].get("success") == false):
		var err = str(res.get("error", res.get("data", {}).get("error", "Unknown error")))
		push_error("批量发放月例失败: %s" % err)
		return

	# 2. 重新计算亏空百分比
	await _recalculate_deficit(total_withheld)

	# 3. 刷新 UI
	_refresh_data()
	print("[TreasuryUI] 批量发放成功")

	# 4. 显示账目信息弹窗
	show_account_summary(distributions, total_withheld)

func _on_ProcureBtn_pressed() -> void:
	_execute_batch_action("procurement")

func _on_AssignTaskBtn_pressed() -> void:
	# 打开差事分派面板
	if assign_task_panel:
		assign_task_panel.visible = true
		_update_task_panel_ui()

# 执行差事分派（带差事类型）
func _execute_assign_task(target_uid: String, silver_reward: int, task_type: String) -> void:
	var task_info = TASK_TYPES.get(task_type, TASK_TYPES["errand"])
	var stamina_cost = task_info.base_cost
	
	# 检查精力是否足够
	if PlayerState.get_current_stamina() < stamina_cost:
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "精力不足，执行该行动需要 %d 点精力" % stamina_cost)
		return
	
	# 调用 RPC
	var params = {
		"p_target_uid": target_uid,
		"p_silver_reward": silver_reward,
		"p_task_type": task_type
	}
	
	var res = await SupabaseManager.db_rpc("steward_assign_task", params)
	var ok: bool = int(res.get("code", 0)) == 200
	if ok:
		var data = res.get("data")
		if data is Dictionary and data.has("success") and data["success"] == false:
			ok = false
	
	if ok:
		# 扣除精力
		if stamina_cost > 0:
			PlayerState.consume_stamina(stamina_cost)
		_refresh_data()
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "差事已分派！")
		# 关闭面板
		if assign_task_panel:
			assign_task_panel.visible = false
	else:
		var err = str(res.get("error", res.get("data", {}).get("error", "未知错误")))
		push_error("差事分派失败：%s" % err)
		if EventBus.has_signal("show_notification"):
			EventBus.emit_signal("show_notification", "差事分派失败：%s" % err)

func _on_SearchGardenBtn_pressed() -> void:
	_execute_batch_action("search")

func _on_AdvanceBtn_pressed() -> void:
	var target_uid := ""
	if player_list and player_list.get_child_count() > 0:
		var first_item = player_list.get_child(0)
		if first_item.has_meta("player_id"):
			target_uid = first_item.get_meta("player_id")
	if target_uid == "":
		push_error("当前无可预支的目标玩家")
		return
	_execute_batch_action("advance", {"target_uid": target_uid})

func _on_SuppressRumorBtn_pressed() -> void:
	# 这里暂时不绑定具体流言，由其他界面传入 rumor_id 时再复用 _execute_batch_action
	push_error("请在流言界面中选择具体流言进行平息")

func _on_BlockInfoBtn_pressed() -> void:
	# 这里暂时不绑定具体情报，由其他界面传入 intel_id 时再复用 _execute_batch_action
	push_error("请在情报界面中选择具体情报进行封锁")

func _on_DebugAllowanceBtn_pressed() -> void:
	# 调试功能：快速发放给第一个玩家
	if player_list and player_list.get_child_count() > 0:
		var first_item = player_list.get_child(0)
		# 找到发放按钮
		for child in first_item.get_children():
			if child is Button and child.text == "发放":
				child.pressed.emit()
				print("[Debug] Triggered first player distribution")
				return
	print("[Debug] No players to distribute to")

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Hub.tscn")

func _on_InboxBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://features/inbox/Inbox.tscn")
