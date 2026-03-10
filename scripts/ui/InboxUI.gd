extends Control

# 门房收件箱 UI 脚本

@onready var back_btn: Button = $Header/BackBtn

func _ready() -> void:
    pass

func _on_BackBtn_pressed() -> void:
    get_tree().change_scene_to_file("res://scenes/Hub.tscn")

