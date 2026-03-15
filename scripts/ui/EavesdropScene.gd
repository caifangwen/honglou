extends Control

# EavesdropScene.gd - 挂机监听选择界面脚本

signal eavesdrop_started(success: bool)

@onready var grid_container = $VBoxContainer/GridContainer
@onready var duration_spin = $VBoxContainer/HBoxContainer/SpinBox
@onready var start_btn = $VBoxContainer/StartBtn
@onready var duo_panel = $VBoxContainer/DuoPanel
@onready var partner_label = $VBoxContainer/DuoPanel/PartnerLabel
@onready var partner_scene_option = $VBoxContainer/DuoPanel/OptionButton
@onready var back_btn = $BackButton
@onready var stamina_label = $VBoxContainer/StaminaLabel
@onready var refresh_btn = $VBoxContainer/RefreshBtn

@onready var error_dialog = $ErrorDialog
@onready var info_dialog = $InfoDialog

var selected_scene = ""
var selected_scene_btn: Button = null
var partner_uid = ""
var partner_name = ""
var _refresh_timer: Timer

func _ready():
	_setup_ui()
	_setup_timers()
	await _check_partner_relationship()
	_refresh_scenes()
	_update_stamina_display()

func _setup_ui():
	# 初始化返回按钮
	back_btn.pressed.connect(_on_back_btn_pressed)
	
	# 初始化刷新按钮
	refresh_btn.pressed.connect(_on_refresh_btn_pressed)

	# 初始化时长选择
	duration_spin.min_value = 1
	duration_spin.max_value = 8
	duration_spin.value = 1
	
	# 时长变化时更新预期收益提示
	duration_spin.value_changed.connect(_on_duration_changed)

	# 初始化按钮
	start_btn.pressed.connect(_on_start_pressed)

	# 初始化对食面板
	duo_panel.hide()

	# 初始化场景卡片
	for scene_key in EavesdropManager.SCENE_CONFIGS.keys():
		var config = EavesdropManager.SCENE_CONFIGS[scene_key]
		var card = _create_scene_card(scene_key, config)
		grid_container.add_child(card)

func _setup_timers():
	# 创建定时器，每 10 秒刷新一次人数
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 10.0
	_refresh_timer.timeout.connect(_refresh_scenes)
	_refresh_timer.autostart = true
	add_child(_refresh_timer)

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
	for card in grid_container.get_children():
		var scene_key = card.name
		var count = await EavesdropManager.get_scene_listener_count(GameState.current_game_id, scene_key)
		var count_label = card.get_node("VBox/CountLabel")
		
		var count_text = "当前人数：%d/5" % count
		if count >= 5:
			count_text += " (拥挤)"
			count_label.add_theme_color_override("font_color", Color.RED)
		elif count >= 3:
			count_text += " (较忙)"
			count_label.remove_theme_color_override("font_color")
		else:
			count_text += " (空闲)"
			count_label.remove_theme_color_override("font_color")
		
		count_label.text = count_text

func _check_partner_relationship():
	# 查询对食关系
	var player_uid = PlayerState.uid
	var endpoint = "/rest/v1/servant_relationships?or=(servant_a=eq.%s,servant_b=eq.%s)&relation_type=eq.duo_shi&select=*" % [player_uid, player_uid]
	var res = await SupabaseManager.db_get(endpoint)

	if res["code"] == 200 and not res["data"].is_empty():
		var rel = res["data"][0]
		partner_uid = rel["servant_b"] if rel["servant_a"] == player_uid else rel["servant_a"]

		# 获取搭档名称
		var p_res = await SupabaseManager.db_get("/rest/v1/players?uid=eq.%s&select=character_name" % partner_uid)
		if p_res["code"] == 200 and not p_res["data"].is_empty():
			partner_name = p_res["data"][0]["character_name"]
			partner_label.text = "搭档：%s" % partner_name
			duo_panel.show()
			_setup_partner_options()
	else:
		duo_panel.hide()

func _setup_partner_options():
	partner_scene_option.clear()
	for scene_key in EavesdropManager.SCENE_CONFIGS.keys():
		var config = EavesdropManager.SCENE_CONFIGS[scene_key]
		partner_scene_option.add_item(config["name"])
		partner_scene_option.set_item_metadata(partner_scene_option.get_item_count() - 1, scene_key)

func _on_scene_selected(key: String, btn: Button):
	selected_scene = key
	
	# 取消其他卡片的选中状态
	for card in grid_container.get_children():
		var other_btn = card.get_node_or_null("VBox/SelectButton")
		if other_btn and other_btn != btn:
			other_btn.button_pressed = false
	
	selected_scene_btn = btn

func _on_duration_changed(_value):
	_update_stamina_display()

func _update_stamina_display():
	var cost = EavesdropManager.COST_STAMINA
	var current = await StaminaManager.get_current_stamina(PlayerState.uid)
	stamina_label.text = "当前精力：%d/%d | 消耗：%d" % [current, PlayerState.stamina_max, cost]
	
	if current < cost:
		stamina_label.add_theme_color_override("font_color", Color.RED)
		start_btn.disabled = true
		start_btn.text = "精力不足"
	else:
		stamina_label.remove_theme_color_override("font_color")
		start_btn.disabled = false
		start_btn.text = "开始挂机"

func _on_start_pressed():
	if selected_scene == "":
		_show_error("请先选择一个监听场景")
		return

	var duration = int(duration_spin.value)
	var p_scene = ""
	
	if duo_panel.visible and partner_uid != "":
		var idx = partner_scene_option.selected
		if idx >= 0:
			p_scene = partner_scene_option.get_item_metadata(idx)

	start_btn.disabled = true
	start_btn.text = "请求中..."

	var success = await EavesdropManager.start_eavesdrop(PlayerState.uid, selected_scene, duration, partner_uid)

	if success:
		if partner_uid != "" and p_scene != "":
			# 搭档挂机（异步，不等待结果）
			EavesdropManager.start_eavesdrop(partner_uid, p_scene, duration, PlayerState.uid)

		_show_info("挂机任务已开始，预计 %d 小时后完成" % duration)
		eavesdrop_started.emit(true)
		
		# 延迟后返回
		await get_tree().create_timer(1.5).timeout
		_on_back_btn_pressed()
	else:
		_show_error("开始挂机失败，请检查精力或网络")
		start_btn.disabled = false
		start_btn.text = "开始挂机"

func _show_error(msg: String):
	error_dialog.dialog_text = msg
	error_dialog.popup_centered()

func _show_info(msg: String):
	info_dialog.dialog_text = msg
	info_dialog.popup_centered()

func _on_back_btn_pressed():
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_refresh_btn_pressed():
	refresh_btn.disabled = true
	refresh_btn.text = "刷新中..."
	await _refresh_scenes()
	refresh_btn.disabled = false
	refresh_btn.text = "刷新"

func _exit_tree():
	if _refresh_timer:
		_refresh_timer.stop()
