extends Control

# 海棠诗社 UI 脚本

@onready var back_btn: Button = %BackBtn

func _ready() -> void:
    $Header/InboxBtn.pressed.connect(_on_InboxBtn_pressed)

func _on_BackBtn_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/main/Hub.tscn")

func _on_InboxBtn_pressed() -> void:
    get_tree().change_scene_to_file("res://features/inbox/Inbox.tscn")

