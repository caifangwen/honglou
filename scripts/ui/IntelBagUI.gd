extends Control

# 情报背包 UI 脚本

@onready var back_btn: Button = $Header/BackBtn
@onready var current_listen_label: Label = $ListenPanel/CurrentListenLabel

func _ready() -> void:
	current_listen_label.text = "当前监听地点：无"

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_YiHongYuanBtn_pressed() -> void:
	_set_listen_location("怡红院后窗")

func _on_TreasuryRoomBtn_pressed() -> void:
	_set_listen_location("管家后账房")

func _on_BridgeBtn_pressed() -> void:
	_set_listen_location("蜂腰桥")

func _on_GateBtn_pressed() -> void:
	_set_listen_location("荣国府大门")

func _on_GrandmaBtn_pressed() -> void:
	_set_listen_location("贾母处")

func _set_listen_location(name: String) -> void:
	current_listen_label.text = "当前监听地点：" + name
	# TODO: 未来在 Firebase 中记录挂机监听请求
