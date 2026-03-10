extends Control

signal login_success()

@onready var name_edit: LineEdit = %NameEdit

func _on_dummy_login_button_pressed() -> void:
	var name: String = name_edit.text.strip_edges()
	if name == "":
		name = "无名氏"
	PlayerState.display_name = name
	PlayerState.uid = str(Time.get_unix_time_from_system())  # 临时 UID
	emit_signal("login_success")
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")
