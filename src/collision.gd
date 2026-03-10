extends Node

const Constants = preload("res://src/constants.gd")

## 轴对齐包围盒重叠检测
static func aabb_overlap(ax: float, ay: float, aw: float, ah: float, bx: float, by: float, bw: float, bh: float) -> bool:
	return ax < bx + bw \
		and ax + aw > bx \
		and ay < by + bh \
		and ay + ah > by


## 检查世界坐标矩形是否与瓦片地图固体层碰撞
## solid_layer: PackedInt32Array 或 Array[int]，长度 = rows * cols
static func check_tile_collision(world_x: float, world_y: float, width: float, height: float, solid_layer: PackedInt32Array, map_cols: int) -> Dictionary:
	var tile_size: int = Constants.TILE["SIZE"]
	var left: int = int(floor(world_x / tile_size))
	var right: int = int(floor((world_x + width - 1.0) / tile_size))
	var top: int = int(floor(world_y / tile_size))
	var bottom: int = int(floor((world_y + height - 1.0) / tile_size))

	var solid_min: int = Constants.COLLISION["SOLID_TILE_MIN"]
	var solid_max: int = Constants.COLLISION["SOLID_TILE_MAX"]

	for row in range(top, bottom + 1):
		for col in range(left, right + 1):
			if row < 0 or col < 0:
				continue
			var idx: int = row * map_cols + col
			if idx < 0 or idx >= solid_layer.size():
				continue
			var tile_id: int = solid_layer[idx]
			if tile_id >= solid_min and tile_id <= solid_max:
				return {
					"hit": true,
					"tile_x": col,
					"tile_y": row,
					"tile_id": tile_id
				}
	return { "hit": false }


## 分轴移动：先 X 再 Y，带瓦片碰撞修正
## player 需要有字段：x, y, vx, vy, on_ground: bool
static func move_with_collision(player: Object, dx: float, dy: float, solid_layer: PackedInt32Array, map_cols: int) -> void:
	var tile_size: int = Constants.TILE["SIZE"]
	var hitbox_w: float = Constants.PLAYER["WIDTH"]
	var hitbox_h: float = Constants.PLAYER["HEIGHT"]
	var off_x: float = Constants.PLAYER["HITBOX_OFFSET_X"]
	var off_y: float = Constants.PLAYER["HITBOX_OFFSET_Y"]

	# === X 轴 ===
	player.x += dx
	var col_x: Dictionary = check_tile_collision(
		player.x + off_x,
		player.y + off_y,
		hitbox_w,
		hitbox_h,
		solid_layer,
		map_cols
	)
	if col_x.get("hit", false):
		if dx > 0.0:
			# 向右碰撞：推回左边界
			player.x = float(col_x["tile_x"] * tile_size) - hitbox_w - off_x
		elif dx < 0.0:
			# 向左碰撞：推到右边界
			player.x = float((col_x["tile_x"] + 1) * tile_size) - off_x
		player.vx = 0.0

	# === Y 轴 ===
	player.y += dy
	var col_y: Dictionary = check_tile_collision(
		player.x + off_x,
		player.y + off_y,
		hitbox_w,
		hitbox_h,
		solid_layer,
		map_cols
	)
	if col_y.get("hit", false):
		if dy > 0.0:
			# 向下碰撞（落地）
			player.y = float(col_y["tile_y"] * tile_size) - hitbox_h - off_y
			player.on_ground = true
		elif dy < 0.0:
			# 向上碰撞（撞顶）
			player.y = float((col_y["tile_y"] + 1) * tile_size) - off_y
		player.vy = 0.0
	else:
		player.on_ground = false

