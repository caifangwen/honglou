extends Node2D

const GameConstants = preload("res://core/constants/GameConstants.gd")
const Collision = preload("res://core/systems/Collision.gd")
const Anim = preload("res://core/systems/Animation.gd")
const PlayerStates = preload("res://core/systems/PlayerStates.gd")

## 逻辑属性（世界坐标单位）
var x: float = 0.0
var y: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var on_ground: bool = false

var state: int = PlayerStates.PlayerState.IDLE
var facing: String = "down"  # "down" | "up" | "side"
var anim_frame: int = 0
var anim_timer: float = 0.0

## 地图/碰撞引用
var current_map: Dictionary


func setup(map_def: Dictionary) -> void:
	current_map = map_def
	var spawn: Dictionary = map_def["spawn"]
	var tile_size: int = GameConstants.TILE["SIZE"]
	x = float(spawn["x"] * tile_size)
	y = float(spawn["y"] * tile_size)


func _physics_process(dt: float) -> void:
	if current_map.is_empty():
		return

	var input_reader: Node = get_parent().get("input_reader")
	if input_reader == null:
		return
	var input: Dictionary = input_reader.read_input()

	_apply_movement(input, dt)

	var special_tile: String = _get_special_tile_under_player()
	PlayerStates.update_player_state(self, input)

	var dx: float = vx * dt
	var dy: float = vy * dt
	var solid_layer: PackedInt32Array = current_map["layers"]["solid"]
	Collision.move_with_collision(self, dx, dy, solid_layer, int(current_map["cols"]))

	Anim.update_animation(self, dt)

	_update_facing_from_input(input)

	var cam: Node = get_parent().get("camera")
	if cam:
		cam.follow(x + GameConstants.PLAYER["WIDTH"] / 2.0, y + GameConstants.PLAYER["HEIGHT"] / 2.0)
		# 逻辑坐标 → 屏幕坐标（不直接修改 Node2D.position，而是渲染时计算）
		# 实际上在本项目框架中，渲染是根据世界坐标偏移来的
	
	# 请求重绘
	queue_redraw()


func _draw() -> void:
	var assets: Node = get_parent().get("assets")
	if assets == null:
		return
	var player_sheet: Texture2D = assets.get_image("player")
	if player_sheet == null:
		return

	var cam: Node = get_parent().get("camera")
	if cam == null:
		return

	# 获取当前动画信息
	var anim_key: String = Anim.get_animation_key(state, facing)
	var anim: Dictionary = Anim.ANIMATIONS.get(anim_key, Anim.ANIMATIONS["idle_down"])

	var tile_size: int = GameConstants.TILE["SIZE"]
	var scale: float = GameConstants.TILE["SCALE"]
	
	# 计算精灵表中的源矩形
	var src_x: float = float(anim_frame * tile_size)
	var src_y: float = float(anim["row"] * tile_size)
	var src_rect: Rect2 = Rect2(src_x, src_y, tile_size, tile_size)
	
	# 计算屏幕坐标
	var screen_pos: Vector2 = cam.world_to_screen(x, y)
	
	draw_texture_rect_region(
		player_sheet,
		Rect2(screen_pos, Vector2(tile_size * scale, tile_size * scale)),
		src_rect
	)


func _apply_movement(input: Dictionary, dt: float) -> void:
	var speed: float = GameConstants.PLAYER["SPEED"]
	var dir: Vector2 = Vector2(input["dx"], input["dy"])
	if dir.length() > 0.0:
		dir = dir.normalized()
	vx = dir.x * speed
	vy = dir.y * speed


func _get_special_tile_under_player() -> String:
	# 预留：可根据当前脚下瓦片的 ID 查找特殊瓦片
	return ""


func _update_facing_from_input(input: Dictionary) -> void:
	if input.get("up", false):
		facing = "up"
	elif input.get("down", false):
		facing = "down"
	elif input.get("left", false) or input.get("right", false):
		facing = "side"
