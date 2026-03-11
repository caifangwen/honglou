extends Node

# 游戏主入口，负责启动和根据登录状态路由

@onready var root_viewport: Viewport = get_viewport()

func _ready() -> void:
	# 1. 仅在调试模式下添加调试时间面板
	if OS.is_debug_build():
		_setup_debug_time_panel()
	
	# 2. 模拟加载当前游戏局 (实际应从登录状态获取)
	var current_game_id = "00000000-0000-0000-0000-000000000001"
	GameTime.load_game_data(current_game_id)

	# TODO: 这里未来可以根据本地缓存 / Firebase 登录状态决定进哪一个场景
	#_go_to_login()
	# 在 _ready 阶段直接切场景会触发「父节点正忙于添加/移除子节点」错误
	# 使用延迟调用，等当前帧完成后再切换场景
	#call_deferred("_go_to_hub")
	call_deferred("_go_to_login")

func _setup_debug_time_panel() -> void:
	var debug_scene = load("res://debug/DebugTimePanel.tscn")
	if debug_scene:
		var debug_panel = debug_scene.instantiate()
		var canvas = CanvasLayer.new()
		canvas.layer = 100 # 置于最顶层
		canvas.add_child(debug_panel)
		add_child(canvas)
		print("[Main] 调试时间面板已集成")

func _go_to_login() -> void:
	get_tree().change_scene_to_file("res://scenes/Login.tscn")

func _go_to_role_select() -> void:
	get_tree().change_scene_to_file("res://scenes/RoleSelect.tscn")

func _go_to_hub() -> void:
	get_tree().change_scene_to_file("res://scenes/Hub.tscn")
