extends Control

# 大观园主界面（导航中心）UI 脚本

@onready var game_day_label: Label = $TopBar/GameDayLabel
@onready var deficit_bar: ProgressBar = $TopBar/DeficitBar
@onready var conflict_bar: ProgressBar = $TopBar/ConflictBar
@onready var character_name_label: Label = $PlayerInfoPanel/VBox/CharacterNameLabel
@onready var role_class_label: Label = $PlayerInfoPanel/VBox/RoleClassLabel
@onready var silver_label: Label = $PlayerInfoPanel/VBox/SilverLabel
@onready var qi_shu_label: Label = $PlayerInfoPanel/VBox/QiShuLabel
@onready var stamina_label: Label = $PlayerInfoPanel/VBox/StaminaLabel

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[HubUI] _gui_input: Mouse click detected at ", event.position)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		print("[HubUI] _input: Global mouse click at ", get_global_mouse_position())

func _ready() -> void:
	print("=== [HubUI] _ready() called ===")
	
	# 强制更新布局
	await get_tree().process_frame
	
	# 直接连接所有按钮信号
	_connect_button("NavigationPanel/NavigationVBox/Row1/TreasuryBtn", _on_TreasuryBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row1/InboxBtn", _on_InboxBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row1/IntelBagBtn", _on_IntelBagBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row2/RumorBoardBtn", _on_RumorBoardBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row2/PoetryHallBtn", _on_PoetryHallBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row2/TimePanelBtn", _on_TimePanelBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row3/MarketBtn", _on_MarketBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row3/EavesdropHubBtn", _on_EavesdropHubBtn_pressed)
	_connect_button("NavigationPanel/NavigationVBox/Row3/EavesdropBtn", _on_EavesdropBtn_pressed)
	
	_init_top_bar()
	_init_player_info()
	GameState.deficit_changed.connect(_on_deficit_changed)
	GameState.conflict_changed.connect(_on_conflict_changed)
	PlayerState.silver_changed.connect(_on_silver_changed)
	PlayerState.qi_shu_changed.connect(_on_qi_shu_changed)
	PlayerState.stamina_changed.connect(_on_stamina_changed)

func _connect_button(path: String, callback: Callable) -> void:
	var btn = get_node_or_null(path)
	if btn and btn is Button:
		btn.pressed.connect(callback)
		print("[HubUI] Connected: ", path)
	else:
		printerr("[HubUI] Button not found: ", path)

func _on_button_debug_print(btn_name: String) -> void:
	print("[HubUI] DEBUG: Button '", btn_name, "' pressed signal received!")
	# 直接调用对应的回调函数
	if btn_name == "TreasuryBtn":
		_on_TreasuryBtn_pressed()
	elif btn_name == "InboxBtn":
		_on_InboxBtn_pressed()
	elif btn_name == "IntelBagBtn":
		_on_IntelBagBtn_pressed()
	elif btn_name == "RumorBoardBtn":
		_on_RumorBoardBtn_pressed()
	elif btn_name == "PoetryHallBtn":
		_on_PoetryHallBtn_pressed()
	elif btn_name == "TimePanelBtn":
		_on_TimePanelBtn_pressed()
	elif btn_name == "MarketBtn":
		_on_MarketBtn_pressed()
	elif btn_name == "EavesdropHubBtn":
		_on_EavesdropHubBtn_pressed()
	elif btn_name == "EavesdropBtn":
		_on_EavesdropBtn_pressed()

func _init_top_bar() -> void:
	game_day_label.text = "第%d日" % GameState.current_day
	deficit_bar.value = GameState.deficit_value
	conflict_bar.value = GameState.internal_conflict

func _init_player_info() -> void:
	character_name_label.text = PlayerState.character_name
	role_class_label.text = PlayerState.role_class
	silver_label.text = "银两：%d" % PlayerState.silver
	qi_shu_label.text = "气数：%d" % PlayerState.qi_shu
	_update_stamina_display()

func _on_deficit_changed(new_value: float) -> void:
	deficit_bar.value = new_value

func _on_conflict_changed(new_value: float) -> void:
	conflict_bar.value = new_value

func _on_silver_changed(new_value: int) -> void:
	silver_label.text = "银两：%d" % new_value

func _on_qi_shu_changed(new_value: int) -> void:
	qi_shu_label.text = "气数：%d" % new_value

func _on_stamina_changed(_new_value: int) -> void:
	_update_stamina_display()

func _update_stamina_display() -> void:
	if is_instance_valid(stamina_label):
		stamina_label.text = "精力：%d/%d" % [PlayerState.get_current_stamina(), PlayerState.stamina_max]

# === 导航按钮回调 ===

func _on_TreasuryBtn_pressed() -> void:
	print("=== [HubUI] TreasuryBtn pressed! ===")
	print("[HubUI] Changing scene to: res://features/treasury/Treasury.tscn")
	var tree = get_tree()
	print("[HubUI] Scene tree valid: ", tree != null)
	var err = tree.change_scene_to_file("res://features/treasury/Treasury.tscn")
	print("[HubUI] change_scene_to_file returned: ", err)

func _on_InboxBtn_pressed() -> void:
	print("=== [HubUI] InboxBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/inbox/Inbox.tscn")

func _on_IntelBagBtn_pressed() -> void:
	print("=== [HubUI] IntelBagBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/eavesdrop/IntelBag.tscn")

func _on_RumorBoardBtn_pressed() -> void:
	print("=== [HubUI] RumorBoardBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/rumor/RumorBoard.tscn")

func _on_PoetryHallBtn_pressed() -> void:
	print("=== [HubUI] PoetryHallBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/poetry/PoetryHall.tscn")

func _on_TimePanelBtn_pressed() -> void:
	print("=== [HubUI] TimePanelBtn pressed! ===")
	get_tree().change_scene_to_file("res://shared/components/TimePanel.tscn")

func _on_MarketBtn_pressed() -> void:
	print("=== [HubUI] MarketBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/market/BridgeMarket.tscn")

func _on_EavesdropBtn_pressed() -> void:
	print("=== [HubUI] EavesdropBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/eavesdrop/EavesdropScene.tscn")

func _on_EavesdropHubBtn_pressed() -> void:
	print("=== [HubUI] EavesdropHubBtn pressed! ===")
	get_tree().change_scene_to_file("res://features/eavesdrop/EavesdropHub.tscn")
