extends Control

# EavesdropScene.gd - 挂机监听选择界面脚本

signal eavesdrop_started(success: bool)

@onready var grid_container = $MainContainer/ScrollContainer/GridContainer
@onready var duration_spin = $MainContainer/ControlPanel/DurationPanel/VBoxContainer/SpinBox
@onready var start_btn = $BottomBar/StartBtn
@onready var duo_panel = $MainContainer/ControlPanel/DuoPanel
@onready var partner_label = $MainContainer/ControlPanel/DuoPanel/VBoxContainer/PartnerLabel
@onready var partner_scene_option = $MainContainer/ControlPanel/DuoPanel/VBoxContainer/OptionButton
@onready var duo_hint_label = $MainContainer/DuoHintLabel
@onready var back_btn = $TopBar/BackButton
@onready var stamina_label = $TopBar/StaminaLabel
@onready var refresh_btn = $TopBar/RefreshBtn
@onready var debug_stamina_btn = $TopBar/DebugStaminaBtn

@onready var error_dialog = $ErrorDialog
@onready var info_dialog = $InfoDialog
@onready var debug_dialog = $DebugDialog

var selected_scene = ""
var selected_scene_btn: Button = null
var partner_uid = ""
var partner_name = ""
var _refresh_timer: Timer

func _ready():
	print("[EavesdropScene] _ready called")
	
	# 先设置静态 UI（不依赖异步数据）
	_setup_static_ui()
	
	# 设置定时器
	_setup_timers()
	
	# 立即刷新场景人数（异步）
	print("[EavesdropScene] Refreshing scenes...")
	await _refresh_scenes()
	
	# 检查对食关系（异步）
	print("[EavesdropScene] Checking partner relationship...")
	await _check_partner_relationship()
	
	# 连接精力变化信号，确保 UI 同步
	if not PlayerState.stamina_changed.is_connected(_on_stamina_changed_signal):
		PlayerState.stamina_changed.connect(_on_stamina_changed_signal)
	
	# 主动刷新一次最新的玩家状态（确保与其他模块同步）
	await _refresh_player_state()
	
	# 更新精力显示
	_update_stamina_display_async()
	
	print("[EavesdropScene] _ready completed")

func _refresh_player_state():
	print("[EavesdropScene] _refresh_player_state called")
	var res = await SupabaseManager.db_get("/rest/v1/players?auth_uid=eq.%s&select=*" % SupabaseManager.current_uid)
	if res["code"] == 200 and not res["data"].is_empty():
		PlayerState.load_from_db(res["data"][0])
		print("[EavesdropScene] PlayerState refreshed from DB")

func _on_stamina_changed_signal(_new_val):
	_update_stamina_display_async()

func _setup_static_ui():
	print("[EavesdropScene] _setup_static_ui called")
	print("[EavesdropScene] grid_container: ", grid_container)
	print("[EavesdropScene] duo_panel: ", duo_panel)
	print("[EavesdropScene] partner_label: ", partner_label)
	print("[EavesdropScene] partner_scene_option: ", partner_scene_option)
	print("[EavesdropScene] duo_hint_label: ", duo_hint_label)

	# 初始化返回按钮
	if is_instance_valid(back_btn):
		back_btn.pressed.connect(_on_back_btn_pressed)
	else:
		printerr("[EavesdropScene] back_btn not found!")

	# 初始化刷新按钮
	if is_instance_valid(refresh_btn):
		refresh_btn.pressed.connect(_on_refresh_btn_pressed)
	else:
		printerr("[EavesdropScene] refresh_btn not found!")

	# 初始化调试精力按钮
	if is_instance_valid(debug_stamina_btn):
		debug_stamina_btn.pressed.connect(_on_debug_stamina_pressed)
	else:
		printerr("[EavesdropScene] debug_stamina_btn not found!")

	# 初始化时长选择
	if is_instance_valid(duration_spin):
		duration_spin.min_value = 1
		duration_spin.max_value = 8
		duration_spin.value = 1
		duration_spin.value_changed.connect(_on_duration_changed)
	else:
		printerr("[EavesdropScene] duration_spin not found!")

	# 初始化按钮
	if is_instance_valid(start_btn):
		start_btn.pressed.connect(_on_start_button_pressed)
	else:
		printerr("[EavesdropScene] start_btn not found!")

	# 初始化对食面板
	if is_instance_valid(duo_panel):
		duo_panel.hide()
		print("[EavesdropScene] duo_panel initialized and hidden")
	else:
		printerr("[EavesdropScene] duo_panel not found!")

	# 初始化搭档提示
	if is_instance_valid(duo_hint_label):
		duo_hint_label.show()
		print("[EavesdropScene] duo_hint_label initialized and shown")
	else:
		printerr("[EavesdropScene] duo_hint_label not found!")

	# 初始化场景卡片
	if is_instance_valid(grid_container):
		print("[EavesdropScene] Creating scene cards...")
		for scene_key in EavesdropManager.SCENE_CONFIGS.keys():
			var config = EavesdropManager.SCENE_CONFIGS[scene_key]
			var card = _create_scene_card(scene_key, config)
			grid_container.add_child(card)
			print("[EavesdropScene] Created card for: %s" % scene_key)
	else:
		printerr("[EavesdropScene] grid_container not found!")

func _setup_timers():
	# 创建定时器，每 10 秒刷新一次人数
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 10.0
	# Godot 4 中，timeout 信号可以连接 async 函数
	_refresh_timer.timeout.connect(_on_refresh_timer_timeout)
	_refresh_timer.autostart = true
	add_child(_refresh_timer)

func _on_refresh_timer_timeout():
	# 定时器刷新（不阻塞 UI）
	_refresh_scenes()

func _create_scene_card(key: String, config: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.name = key
	card.custom_minimum_size = Vector2(220, 180)
	card.tooltip_text = config.get("description", "")

	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	card.add_child(vbox)
	
	# 场景名称
	var name_label = Label.new()
	name_label.text = config["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.add_theme_font_size_override("font_size", 18)
	vbox.add_child(name_label)
	
	# 人数标签
	var count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.text = "加载中..."
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(count_label)
	
	# 描述
	var desc_label = Label.new()
	desc_label.text = config.get("description", "")
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_label.add_theme_color_override("font_color", Color.GRAY)
	vbox.add_child(desc_label)
	
	# 情报类型
	var type_label = Label.new()
	type_label.text = "情报：" + ", ".join(config["intel_type"])
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(type_label)
	
	# 价值星级
	var value_label = Label.new()
	value_label.text = "预期收益：" + _get_stars(config["value_range"][0], config["value_range"][1])
	value_label.add_theme_color_override("font_color", Color.GOLD)
	vbox.add_child(value_label)
	
	# 成功率
	var rate_label = Label.new()
	rate_label.text = "基础成功率：%d%%" % int(config["base_rate"] * 100)
	rate_label.add_theme_color_override("font_color", Color.LIME_GREEN)
	vbox.add_child(rate_label)
	
	# 选择按钮
	var select_btn = Button.new()
	select_btn.name = "SelectButton"
	select_btn.text = "选择此场景"
	select_btn.toggle_mode = true
	select_btn.pressed.connect(func(): _on_scene_selected(key, select_btn))
	vbox.add_child(select_btn)

	return card

func _get_stars(min_val: int, max_val: int) -> String:
	var avg = (min_val + max_val) / 2
	var stars = ""
	for i in range(5):
		if i < avg:
			stars += "★"
		else:
			stars += "☆"
	return stars

func _refresh_scenes():
	print("[EavesdropScene] _refresh_scenes called")
	
	# 检查场景是否仍然有效
	if not is_instance_valid(self) or not is_instance_valid(grid_container):
		print("[EavesdropScene] _refresh_scenes: self or grid_container invalid")
		return

	print("[EavesdropScene] _refresh_scenes: current_game_id=", GameState.current_game_id)
	
	for card in grid_container.get_children():
		var scene_key = card.name
		# 直接通过 get_node 查找，不使用 get_node_or_null
		var count_label = card.get_node("VBox/CountLabel")
		
		if not is_instance_valid(count_label):
			print("[EavesdropScene] CountLabel not found for card: ", scene_key, ", children: ", card.get_children())
			continue
			
		# 先显示加载中
		count_label.text = "加载中..."
		
		var count = await EavesdropManager.get_scene_listener_count(GameState.current_game_id, scene_key)
		print("[EavesdropScene] Scene ", scene_key, " count: ", count)

		var count_text = "当前人数：%d/5" % count
		if count >= 5:
			count_text += " (拥挤)"
			count_label.remove_theme_color_override("font_color")
			count_label.add_theme_color_override("font_color", Color.RED)
		elif count >= 3:
			count_text += " (较忙)"
			count_label.remove_theme_color_override("font_color")
			count_label.add_theme_color_override("font_color", Color.ORANGE)
		else:
			count_text += " (空闲)"
			count_label.remove_theme_color_override("font_color")
			count_label.add_theme_color_override("font_color", Color.LIME_GREEN)

		count_label.text = count_text

func _check_partner_relationship():
	print("[EavesdropScene] _check_partner_relationship called")
	print("[EavesdropScene] duo_panel valid: ", is_instance_valid(duo_panel))
	print("[EavesdropScene] partner_label valid: ", is_instance_valid(partner_label))
	print("[EavesdropScene] partner_scene_option valid: ", is_instance_valid(partner_scene_option))
	
	# 检查节点是否有效
	if not is_instance_valid(duo_panel) or not is_instance_valid(partner_label) or not is_instance_valid(partner_scene_option):
		print("[EavesdropScene] duo_panel or partner controls invalid")
		print("[EavesdropScene] duo_panel: ", duo_panel)
		print("[EavesdropScene] partner_label: ", partner_label)
		print("[EavesdropScene] partner_scene_option: ", partner_scene_option)
		return

	# 查询对食关系
	var player_uid = PlayerState.uid
	print("[EavesdropScene] Checking partner relationship for player: ", player_uid)
	
	# 使用 maid_relationships 表查询
	var endpoint = "/rest/v1/maid_relationships?or=(player_a_uid=eq.%s,player_b_uid=eq.%s)&relation_type=eq.dui_shi&status=eq.active&select=*" % [player_uid, player_uid]
	print("[EavesdropScene] Query endpoint: ", endpoint)
	var res = await SupabaseManager.db_get(endpoint)
	
	print("[EavesdropScene] Partner query result: code=", res.get("code", "N/A"), ", data=", res.get("data", "N/A"))

	if res["code"] == 200 and not res["data"].is_empty():
		var rel = res["data"][0]
		partner_uid = rel["player_b_uid"] if rel["player_a_uid"] == player_uid else rel["player_a_uid"]
		print("[EavesdropScene] Found partner UID: ", partner_uid)

		# 获取搭档名称
		var p_res = await SupabaseManager.db_get("/rest/v1/players?id=eq.%s&select=character_name" % partner_uid)
		if p_res["code"] == 200 and not p_res["data"].is_empty():
			partner_name = p_res["data"][0]["character_name"]
			partner_label.text = "搭档：%s" % partner_name
			duo_panel.show()
			if is_instance_valid(duo_hint_label):
				duo_hint_label.hide()
			_setup_partner_options()
			print("[EavesdropScene] Partner found: ", partner_name)
		else:
			print("[EavesdropScene] Failed to get partner name: code=", p_res.get("code", "N/A"))
			if is_instance_valid(duo_hint_label):
				duo_hint_label.show()
	else:
		print("[EavesdropScene] No partner found or query failed")
		duo_panel.hide()
		# 显示提示
		if is_instance_valid(duo_hint_label):
			duo_hint_label.show()

func _setup_partner_options():
	partner_scene_option.clear()
	for scene_key in EavesdropManager.SCENE_CONFIGS.keys():
		var config = EavesdropManager.SCENE_CONFIGS[scene_key]
		partner_scene_option.add_item(config["name"])
		partner_scene_option.set_item_metadata(partner_scene_option.get_item_count() - 1, scene_key)

func _on_scene_selected(key: String, btn: Button):
	print("[EavesdropScene] _on_scene_selected: ", key)
	selected_scene = key

	# 取消其他卡片的选中状态
	for card in grid_container.get_children():
		var other_btn = card.get_node_or_null("VBox/SelectButton")
		if other_btn and other_btn != btn:
			other_btn.button_pressed = false

	selected_scene_btn = btn
	print("[EavesdropScene] Scene selected, btn pressed: ", btn.button_pressed)

func _on_duration_changed(_value):
	# 异步更新精力显示
	_update_stamina_display_async()

func _update_stamina_display_async():
	var cost = EavesdropManager.COST_STAMINA
	# 直接使用 PlayerState 的精力值，而不是查询数据库
	var current = PlayerState.get_current_stamina()
	var max_val = PlayerState.stamina_max
	# 详细显示精力信息
	stamina_label.text = "精力：%d/%d  消耗：%d  最后刷新：%d 秒前" % [
		current, 
		max_val, 
		cost,
		int(Time.get_unix_time_from_system()) - PlayerState.last_stamina_refresh
	]

	if current < cost:
		stamina_label.add_theme_color_override("font_color", Color.RED)
		if is_instance_valid(start_btn):
			start_btn.disabled = true
			start_btn.text = "精力不足"
	else:
		stamina_label.remove_theme_color_override("font_color")
		if is_instance_valid(start_btn):
			start_btn.disabled = false
			start_btn.text = "开始挂机"

func _on_debug_stamina_pressed():
	print("[EavesdropScene] _on_debug_stamina_pressed called")
	
	# 显示当前精力状态
	var current = PlayerState.get_current_stamina()
	var max_val = PlayerState.stamina_max
	var last_refresh = int(Time.get_unix_time_from_system()) - PlayerState.last_stamina_refresh
	
	var debug_info = """
=== 精力状态调试信息 ===

当前精力： %d / %d
挂机消耗： %d
最后刷新： %d 秒前 (%.1f 分钟前)
预计恢复： %.1f 小时后恢复 1 点

操作：点击确定按钮增加 3 点精力
""" % [
		current, 
		max_val, 
		EavesdropManager.COST_STAMINA,
		last_refresh,
		last_refresh / 60.0,
		(GameConfig.STAMINA_RECOVERY_SEC - last_refresh) / 3600.0
	]
	
	if debug_dialog:
		debug_dialog.dialog_text = debug_info
		debug_dialog.title = "精力调试 - 当前：%d/%d" % [current, max_val]
		debug_dialog.popup_centered()
		
		# 连接 confirmed 信号（一次性）
		debug_dialog.confirmed.connect(_on_debug_stamina_confirm, CONNECT_ONE_SHOT)
	else:
		# 如果没有对话框，直接增加精力
		_add_debug_stamina()

func _on_debug_stamina_confirm():
	_add_debug_stamina()

func _add_debug_stamina():
	PlayerState.stamina = min(PlayerState.stamina + 3, PlayerState.stamina_max)
	# 不需要手动设置 last_stamina_refresh，setter 已经处理了
	
	print("[EavesdropScene] 调试：精力已设置为 %d/%d" % [PlayerState.stamina, PlayerState.stamina_max])
	
	# 同步到数据库，使其他场景可见
	await PlayerState.sync_to_db()
	
	# 更新显示
	_update_stamina_display_async()
	
	_show_info("精力已补充 3 点，当前：%d/%d (已同步至云端)" % [PlayerState.stamina, PlayerState.stamina_max])

func _on_start_pressed():
	print("[EavesdropScene] _on_start_pressed called")
	
	# 调试：检查 PlayerState 和 GameState
	print("[EavesdropScene] === 状态检查 ===")
	print("[EavesdropScene] PlayerState.uid: ", PlayerState.uid)
	print("[EavesdropScene] PlayerState.player_db_id: ", PlayerState.player_db_id)
	print("[EavesdropScene] PlayerState.current_game_id: ", PlayerState.current_game_id)
	print("[EavesdropScene] GameState.current_game_id: ", GameState.current_game_id)
	print("[EavesdropScene] PlayerState.stamina: ", PlayerState.stamina)
	print("[EavesdropScene] PlayerState.get_current_stamina(): ", PlayerState.get_current_stamina())
	print("[EavesdropScene] PlayerState.role_class: ", PlayerState.role_class)
	print("[EavesdropScene] selected_scene: ", selected_scene)

	if selected_scene == "":
		print("[EavesdropScene] No scene selected")
		_show_error("请先选择一个监听场景")
		return

	# 检查 duration_spin 是否有效，如果无效使用默认值
	var duration = 1
	if is_instance_valid(duration_spin):
		duration = int(duration_spin.value)
		print("[EavesdropScene] duration_spin value: ", duration)
	else:
		print("[EavesdropScene] duration_spin is invalid, using default duration=1")

	var p_scene = ""

	if is_instance_valid(duo_panel) and duo_panel.visible and partner_uid != "":
		if is_instance_valid(partner_scene_option):
			var idx = partner_scene_option.selected
			if idx >= 0:
				p_scene = partner_scene_option.get_item_metadata(idx)
				print("[EavesdropScene] Partner scene: ", p_scene)

	# 检查精力（使用 get_current_stamina 获取实际精力）
	var current_stamina = PlayerState.get_current_stamina()
	print("[EavesdropScene] 精力检查：当前=%d, 需要=%d" % [current_stamina, EavesdropManager.COST_STAMINA])
	
	if current_stamina < EavesdropManager.COST_STAMINA:
		print("[EavesdropScene] 精力不足！stamina=%d, get_current_stamina()=%d" % [PlayerState.stamina, current_stamina])
		_show_error("精力不足，需要 %d 点，当前只有 %d 点" % [EavesdropManager.COST_STAMINA, current_stamina])
		return

	print("[EavesdropScene] Starting eavesdrop: scene=", selected_scene, ", duration=", duration, ", partner=", (partner_uid if partner_uid != "" else "none"))
	start_btn.disabled = true
	start_btn.text = "请求中..."

	var success = await EavesdropManager.start_eavesdrop(PlayerState.uid, selected_scene, duration, partner_uid)
	
	print("[EavesdropScene] start_eavesdrop returned: ", success)

	if success:
		if partner_uid != "" and p_scene != "":
			print("[EavesdropScene] Starting partner eavesdrop for: ", partner_uid)
			EavesdropManager.start_eavesdrop(partner_uid, p_scene, duration, PlayerState.uid)

		_show_info("挂机任务已开始，预计 %d 小时后完成" % duration)
		eavesdrop_started.emit(true)

		# 延迟后返回，使用 call_deferred 避免场景切换问题
		await get_tree().create_timer(1.5).timeout
		if is_instance_valid(self):
			get_tree().change_scene_to_file.call_deferred("res://scenes/main/Hub.tscn")
	else:
		_show_error("开始挂机失败，请查看控制台日志获取详细信息")
		start_btn.disabled = false
		start_btn.text = "开始挂机"

# 包装函数，用于信号连接 - Godot 4 中信号连接的 async 函数需要这样处理
func _on_start_button_pressed():
	print("[EavesdropScene] _on_start_button_pressed called")
	print("[EavesdropScene] duration_spin valid: ", is_instance_valid(duration_spin), ", selected_scene: ", selected_scene)
	await _on_start_pressed()

func _show_error(msg: String):
	error_dialog.dialog_text = msg
	error_dialog.popup_centered()

func _show_info(msg: String):
	info_dialog.dialog_text = msg
	info_dialog.popup_centered()

func _on_back_btn_pressed():
	print("[EavesdropScene] _on_back_btn_pressed called")
	var tree = get_tree()
	if not tree or not is_instance_valid(tree):
		return
	var err = tree.change_scene_to_file("res://scenes/main/Hub.tscn")
	if err != OK:
		push_error("[EavesdropScene] Failed to change scene: %d" % err)

func _on_refresh_btn_pressed():
	if not is_instance_valid(refresh_btn):
		return
	refresh_btn.disabled = true
	refresh_btn.text = "刷新中..."
	await _refresh_scenes()
	if is_instance_valid(refresh_btn):
		refresh_btn.disabled = false
		refresh_btn.text = "刷新"

func _exit_tree():
	if _refresh_timer:
		_refresh_timer.stop()
		_refresh_timer.queue_free()
