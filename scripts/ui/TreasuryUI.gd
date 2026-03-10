extends Control

# 银库界面 UI 脚本

@onready var back_btn: Button = $Header/BackBtn
@onready var total_silver_label: Label = $Header/TotalSilverLabel
@onready var stamina_display: Label = $ActionPanel/StaminaDisplay

func _ready() -> void:
	_refresh_header()
	_refresh_stamina()

func _refresh_header() -> void:
	# TODO: 从 Firebase 载入真实银库总额
	total_silver_label.text = "总银两：--"

func _refresh_stamina() -> void:
	stamina_display.text = "精力：%d / %d" % [PlayerState.get_current_stamina(), PlayerState.stamina_max]

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_ConfirmAllocationBtn_pressed() -> void:
	# TODO: 发送分配指令到 Firebase
	pass

func _on_ProcureBtn_pressed() -> void:
	_try_consume_stamina(GameConfig.COST_PROCURE)

func _on_AssignTaskBtn_pressed() -> void:
	_try_consume_stamina(GameConfig.COST_ASSIGN_TASK)

func _on_SearchGardenBtn_pressed() -> void:
	_try_consume_stamina(GameConfig.COST_SEARCH_GARDEN)

func _on_AdvanceBtn_pressed() -> void:
	_try_consume_stamina(GameConfig.COST_ADVANCE_PAYMENT)

func _on_SuppressRumorBtn_pressed() -> void:
	_try_consume_stamina(GameConfig.COST_SUPPRESS_RUMOR)

func _on_BlockInfoBtn_pressed() -> void:
	_try_consume_stamina(GameConfig.COST_BLOCK_INFO)

func _try_consume_stamina(cost: int) -> void:
	if PlayerState.consume_stamina(cost):
		_refresh_stamina()
	else:
		push_warning("精力不足，无法执行该行动")
