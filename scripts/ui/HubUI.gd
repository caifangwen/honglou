extends Control

# 大观园主界面（导航中心）UI 脚本

@onready var game_day_label: Label = $TopBar/GameDayLabel
@onready var deficit_bar: ProgressBar = $TopBar/DeficitBar
@onready var conflict_bar: ProgressBar = $TopBar/ConflictBar
@onready var character_name_label: Label = $PlayerInfoPanel/VBox/CharacterNameLabel
@onready var role_class_label: Label = $PlayerInfoPanel/VBox/RoleClassLabel
@onready var silver_label: Label = $PlayerInfoPanel/VBox/SilverLabel
@onready var qi_shu_label: Label = $PlayerInfoPanel/VBox/QiShuLabel

func _ready() -> void:
	_init_top_bar()
	_init_player_info()
	GameState.deficit_changed.connect(_on_deficit_changed)
	GameState.conflict_changed.connect(_on_conflict_changed)
	PlayerState.silver_changed.connect(_on_silver_changed)
	PlayerState.qi_shu_changed.connect(_on_qi_shu_changed)
	PlayerState.stamina_changed.connect(_on_stamina_changed)

func _init_top_bar() -> void:
	game_day_label.text = "第%d日" % GameState.current_day
	deficit_bar.value = GameState.deficit_value
	conflict_bar.value = GameState.internal_conflict

func _init_player_info() -> void:
	character_name_label.text = PlayerState.character_name
	role_class_label.text = PlayerState.role_class
	silver_label.text = str(PlayerState.silver)
	qi_shu_label.text = str(PlayerState.qi_shu)

func _on_deficit_changed(new_value: float) -> void:
	deficit_bar.value = new_value

func _on_conflict_changed(new_value: float) -> void:
	conflict_bar.value = new_value

func _on_silver_changed(new_value: int) -> void:
	silver_label.text = str(new_value)

func _on_qi_shu_changed(new_value: int) -> void:
	qi_shu_label.text = str(new_value)

func _on_stamina_changed(_new_value: int) -> void:
	# 如果有精力条也可以在这里更新
	pass

# === 导航按钮回调 ===

func _on_TreasuryBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Treasury.tscn")

func _on_InboxBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Inbox.tscn")

func _on_IntelBagBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/IntelBag.tscn")

func _on_RumorBoardBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/RumorBoard.tscn")

func _on_PoetryHallBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/PoetryHall.tscn")

func _on_MarketBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Market.tscn")

func _on_EavesdropBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/ui/EavesdropScene.tscn")

func _on_DebugBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/DebugPanel.tscn")
