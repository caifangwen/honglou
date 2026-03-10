extends Node

# 游戏主入口，负责启动和根据登录状态路由

@onready var root_viewport: Viewport = get_viewport()

func _ready() -> void:
	# TODO: 这里未来可以根据本地缓存 / Firebase 登录状态决定进哪一个场景
	#_go_to_login()
	_go_to_hub()

func _go_to_login() -> void:
	get_tree().change_scene_to_file("res://scenes/Login.tscn")

func _go_to_role_select() -> void:
	get_tree().change_scene_to_file("res://scenes/RoleSelect.tscn")

func _go_to_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")
