extends Node

# 游戏主入口，负责启动和根据登录状态路由

@onready var root_viewport: Viewport = get_viewport()

func _ready() -> void:
	print("=== [Main] _ready() called ===")
	print("[Main] Scene path: ", get_tree().current_scene.get_path())
	
	# 1. 仅在调试模式下添加调试时间面板
	if OS.is_debug_build():
		_setup_debug_time_panel()

	# 2. 模拟加载当前游戏局 (实际应从登录状态获取)
	var current_game_id = "00000000-0000-0000-0000-000000000001"
	GameTime.load_game_data(current_game_id)

	# 默认从登录开始
	call_deferred("_go_to_login")

func _setup_debug_time_panel() -> void:
	var debug_scene = load("res://scenes/debug/DebugTimePanel.tscn")
	if debug_scene:
		var debug_panel = debug_scene.instantiate()
		var canvas = CanvasLayer.new()
		canvas.layer = 100 # 置于最顶层
		canvas.add_child(debug_panel)
		add_child(canvas)
		print("[Main] 调试时间面板已集成")

func _go_to_login() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Login.tscn")

func _go_to_role_select() -> void:
	get_tree().change_scene_to_file("res://scenes/main/RoleSelect.tscn")

func _go_to_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/main/Hub.tscn")
