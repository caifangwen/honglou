extends Control

# EavesdropScene.gd - 挂机监听选择界面脚本

@onready var grid_container = $VBoxContainer/GridContainer
@onready var duration_spin = $VBoxContainer/HBoxContainer/SpinBox
@onready var start_btn = $VBoxContainer/StartBtn
@onready var duo_panel = $VBoxContainer/DuoPanel
@onready var partner_label = $VBoxContainer/DuoPanel/PartnerLabel
@onready var partner_scene_option = $VBoxContainer/DuoPanel/OptionButton
@onready var back_btn = $BackButton

var selected_scene = ""
var partner_uid = ""
var partner_name = ""

func _ready():
	_setup_ui()
	_refresh_scenes()
	_check_partner_relationship()

func _setup_ui():
	# 初始化返回按钮
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/Hub.tscn"))
	
	# 初始化时长选择
	duration_spin.min_value = 1
	duration_spin.max_value = 8
	duration_spin.value = 1
	
	# 初始化按钮
	start_btn.pressed.connect(_on_start_pressed)
	
	# 初始化对食面板
	duo_panel.hide()
	
	# 初始化场景卡片
	for scene_key in EavesdropManager.SCENE_CONFIGS.keys():
		var config = EavesdropManager.SCENE_CONFIGS[scene_key]
		var card = _create_scene_card(scene_key, config)
		grid_container.add_child(card)

func _create_scene_card(key: String, config: Dictionary) -> PanelContainer:
	var card = PanelContainer.new()
	card.name = key
	card.custom_minimum_size = Vector2(200, 150)
	
	var vbox = VBoxContainer.new()
	vbox.name = "VBox"
	card.add_child(vbox)
	
	var name_label = Label.new()
	name_label.text = config["name"]
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(name_label)
	
	var count_label = Label.new()
	count_label.name = "CountLabel"
	count_label.text = "加载中..."
	vbox.add_child(count_label)
	
	var type_label = Label.new()
	type_label.text = "情报: " + ", ".join(config["intel_type"])
	type_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(type_label)
	
	var profit_label = Label.new()
	profit_label.text = "预期收益: " + str(config["value_range"][0]) + "-" + str(config["value_range"][1]) + "级"
	vbox.add_child(profit_label)
	
	var select_btn = Button.new()
	select_btn.name = "SelectButton"
	select_btn.text = "选择此场景"
	select_btn.toggle_mode = true
	select_btn.pressed.connect(func(): _on_scene_selected(key, select_btn))
	vbox.add_child(select_btn)
	
	return card

func _refresh_scenes():
	for card in grid_container.get_children():
		var scene_key = card.name
		var count = await EavesdropManager.get_scene_listener_count(GameState.current_game_id, scene_key)
		var count_label = card.get_node("VBox/CountLabel")
		count_label.text = "当前人数: %d/5" % count
		if count >= 5:
			count_label.add_theme_color_override("font_color", Color.RED)

func _check_partner_relationship():
	# 查询对食关系 (假设存在 servant_relationships 表)
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
			partner_label.text = "搭档: " + partner_name
			duo_panel.show()
			_setup_partner_options()

func _setup_partner_options():
	partner_scene_option.clear()
	for scene_key in EavesdropManager.SCENE_CONFIGS.keys():
		partner_scene_option.add_item(EavesdropManager.SCENE_CONFIGS[scene_key]["name"])
		partner_scene_option.set_item_metadata(partner_scene_option.get_item_count() - 1, scene_key)

func _on_scene_selected(key: String, btn: Button):
	selected_scene = key
	# 取消其他卡片的选中状态
	for card in grid_container.get_children():
		var other_btn = card.get_node("VBox/SelectButton")
		if other_btn != btn:
			other_btn.button_pressed = false

func _on_start_pressed():
	if selected_scene == "":
		_show_error("请先选择一个监听场景")
		return
	
	var duration = int(duration_spin.value)
	var p_scene = ""
	if duo_panel.visible:
		var idx = partner_scene_option.get_selected_id()
		p_scene = partner_scene_option.get_item_metadata(idx)
	
	start_btn.disabled = true
	start_btn.text = "请求中..."
	
	var success = await EavesdropManager.start_eavesdrop(PlayerState.uid, selected_scene, duration, partner_uid)
	
	if success:
		if partner_uid != "" and p_scene != "":
			# 如果有搭档，开启第二场景挂机
			await EavesdropManager.start_eavesdrop(partner_uid, p_scene, duration, PlayerState.uid)
		
		_show_info("挂机任务已开始")
		# 可以在这里关闭界面或跳转
	else:
		_show_error("开始挂机失败，请检查精力或网络")
		start_btn.disabled = false
		start_btn.text = "开始挂机"

func _show_error(msg: String):
	# 实际应使用弹窗
	push_warning(msg)

func _show_info(msg: String):
	# 实际应使用弹窗
	print(msg)
