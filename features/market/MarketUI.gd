extends Control

# 蜂腰桥集市 占位界面

func _ready() -> void:
	$Header/InboxBtn.pressed.connect(_on_InboxBtn_pressed)

func _on_BackBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Hub.tscn")

func _on_InboxBtn_pressed() -> void:
	get_tree().change_scene_to_file("res://features/inbox/Inbox.tscn")

