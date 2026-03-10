extends Node

const Constants = preload("res://src/constants.gd")


var x: float = 0.0
var y: float = 0.0
var w: float = 0.0
var h: float = 0.0
var bound_w: float = 0.0
var bound_h: float = 0.0


func _init(viewport_w: float, viewport_h: float, map_w_tiles: int, map_h_tiles: int) -> void:
	var scale: float = Constants.TILE["SCALE"]
	var tile_size: float = Constants.TILE["SIZE"]
	w = viewport_w / scale
	h = viewport_h / scale
	bound_w = map_w_tiles * tile_size
	bound_h = map_h_tiles * tile_size


## 每帧调用，带死区与缓动
func follow(target_x: float, target_y: float) -> void:
	var center_x: float = target_x - w / 2.0
	var center_y: float = target_y - h / 2.0

	var deadzone_x: float = Constants.CAMERA["DEADZONE_X"]
	var deadzone_y: float = Constants.CAMERA["DEADZONE_Y"]
	var lerp_factor: float = Constants.CAMERA["LERP"]

	var dead_left: float = x + w / 2.0 - deadzone_x
	var dead_right: float = x + w / 2.0 + deadzone_x
	var dead_top: float = y + h / 2.0 - deadzone_y
	var dead_bottom: float = y + h / 2.0 + deadzone_y

	var target_cam_x: float = x
	var target_cam_y: float = y

	if target_x < dead_left:
		target_cam_x = center_x
	if target_x > dead_right:
		target_cam_x = center_x
	if target_y < dead_top:
		target_cam_y = center_y
	if target_y > dead_bottom:
		target_cam_y = center_y

	# 缓动
	x += (target_cam_x - x) * lerp_factor
	y += (target_cam_y - y) * lerp_factor

	# 边界夹紧
	x = clamp(x, 0.0, max(0.0, bound_w - w))
	y = clamp(y, 0.0, max(0.0, bound_h - h))


## 世界坐标 → 屏幕坐标（像素）
func world_to_screen(world_x: float, world_y: float) -> Vector2:
	var scale: float = Constants.TILE["SCALE"]
	return Vector2((world_x - x) * scale, (world_y - y) * scale)

