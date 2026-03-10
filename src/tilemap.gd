extends Node2D

const Constants = preload("res://src/constants.gd")

## 负责按视口裁剪绘制四个地图层

var map_def: Dictionary
var tileset: Texture2D


func setup(_map_def: Dictionary, _tileset: Texture2D) -> void:
	map_def = _map_def
	tileset = _tileset


func _process(_dt: float) -> void:
	# 地图也需要随摄像机移动而请求重绘
	queue_redraw()


func _draw() -> void:
	if map_def.is_empty() or tileset == null:
		return

	var camera: Node = get_parent().get("camera")
	if camera == null:
		return

	var tile_size: int = Constants.TILE["SIZE"]
	var scale: float = Constants.TILE["SCALE"]
	var cols: int = map_def["cols"]
	var rows: int = map_def["rows"]
	var tileset_cols: int = map_def["tileset_cols"]

	var layers: Dictionary = map_def["layers"]
	var total_cols: int = map_def["cols"]

	# 视口裁剪范围（世界坐标 → 瓦片索引）
	var start_col: int = maxi(0, int(floor(camera.x / tile_size)))
	var end_col: int = mini(cols - 1, int(ceil((camera.x + camera.w) / tile_size)))
	var start_row: int = maxi(0, int(floor(camera.y / tile_size)))
	var end_row: int = mini(rows - 1, int(ceil((camera.y + camera.h) / tile_size)))

	_draw_layer(layers["bg"], tileset_cols, start_col, end_col, start_row, end_row, tile_size, scale, camera, total_cols)
	_draw_layer(layers["deco"], tileset_cols, start_col, end_col, start_row, end_row, tile_size, scale, camera, total_cols)
	# 玩家在 Tilemap 之上的单独节点绘制
	_draw_layer(layers["above"], tileset_cols, start_col, end_col, start_row, end_row, tile_size, scale, camera, total_cols)


func _draw_layer(layer: PackedInt32Array, tileset_cols: int, start_col: int, end_col: int, start_row: int, end_row: int, tile_size: int, scale: float, camera, total_cols: int) -> void:
	if layer == null or layer.size() == 0:
		return

	for row in range(start_row, end_row + 1):
		for col in range(start_col, end_col + 1):
			var idx: int = row * total_cols + col
			if idx < 0 or idx >= layer.size():
				continue
			var tile_id: int = layer[idx]
			if tile_id == 0:
				continue
			var src_rect: Rect2 = _get_tile_source_rect(tile_id, tileset_cols, tile_size)
			if src_rect == Rect2():
				continue
			var screen_x: float = (col * tile_size - camera.x) * scale
			var screen_y: float = (row * tile_size - camera.y) * scale
			draw_texture_rect_region(
				tileset,
				Rect2(Vector2(screen_x, screen_y), Vector2(tile_size * scale, tile_size * scale)),
				src_rect
			)


func _get_tile_source_rect(tile_id: int, tileset_cols: int, tile_size: int) -> Rect2:
	if tile_id == 0:
		return Rect2()
	var id: int = tile_id - 1
	var col: int = id % tileset_cols
	var row: int = id / tileset_cols
	return Rect2(
		Vector2(col * tile_size, row * tile_size),
		Vector2(tile_size, tile_size)
	)
