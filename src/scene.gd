extends Node

## 场景 / 地图管理

const Map01 = preload("res://src/maps/map_01.gd")
const Map02 = preload("res://src/maps/map_02.gd")

var current_map: Dictionary


func load_map(id: String) -> Dictionary:
	match id:
		"map_01":
			current_map = Map01.get_map_def()
		"map_02":
			current_map = Map02.get_map_def()
		_:
			current_map = Map01.get_map_def()
	return current_map


func check_portals(player_pos: Vector2) -> Dictionary:
	if current_map.is_empty():
		return {}
	var tile_size: int = preload("res://src/constants.gd").TILE["SIZE"]
	var px: int = int(player_pos.x / tile_size)
	var py: int = int(player_pos.y / tile_size)
	for portal in current_map["portals"]:
		if portal["x"] == px and portal["y"] == py:
			return portal
	return {}

