extends Control

# 流言广场 UI 脚本

@onready var back_btn: Button = $Header/BackBtn
@onready var stamina_cost_label: Label = $PublishPanel/StaminaCostLabel

func _ready() -> void:
	stamina_cost_label.text = "消耗：%d点精力" % GameConfig.COST_PUBLISH_RUMOR

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")

func _on_PublishBtn_pressed() -> void:
	# TODO: 校验精力并向 Firebase 发送流言
	EventBus.rumor_published.emit({})
