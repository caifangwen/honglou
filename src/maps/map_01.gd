extends Resource

const Constants = preload("res://src/constants.gd")

## 简单示例地图（20x15，全空白，可作为框架占位）

const ID := "map_01"
const NAME := "起始小屋"

const COLS := Constants.MAP["COLS"]
const ROWS := Constants.MAP["ROWS"]

const TILESET_SRC := "res://assets/tileset_world.png"
const TILESET_COLS := 8

## 为了简单先全部填 0，实际项目中可以由外部编辑器导出后填充
static var LAYER_BG: PackedInt32Array = _generate_flat_map(1)  # 填充 ID 为 1 的瓦片
static var LAYER_DECO: PackedInt32Array = PackedInt32Array([])
static var LAYER_SOLID: PackedInt32Array = PackedInt32Array([])
static var LAYER_ABOVE: PackedInt32Array = PackedInt32Array([])

static func _generate_flat_map(tile_id: int) -> PackedInt32Array:
	var arr: PackedInt32Array = PackedInt32Array()
	arr.resize(COLS * ROWS)
	arr.fill(tile_id)
	return arr

const PORTALS := [
	{
		"x": 19,
		"y": 7,
		"direction": "EAST",
		"target_map": "map_02",
		"spawn_x": 0,
		"spawn_y": 7
	}
]

const SPAWN := { "x": 2, "y": 7 }


static func get_map_def() -> Dictionary:
	return {
		"id": ID,
		"name": NAME,
		"cols": COLS,
		"rows": ROWS,
		"tileset_src": TILESET_SRC,
		"tileset_cols": TILESET_COLS,
		"layers": {
			"bg": LAYER_BG,
			"deco": LAYER_DECO,
			"solid": LAYER_SOLID,
			"above": LAYER_ABOVE
		},
		"portals": PORTALS,
		"spawn": SPAWN
	}
