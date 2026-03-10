extends Resource

const Constants = preload("res://src/constants.gd")

const ID := "map_02"
const NAME := "室外示例"

const COLS := Constants.MAP["COLS"]
const ROWS := Constants.MAP["ROWS"]

const TILESET_SRC := "res://assets/tileset_world.png"
const TILESET_COLS: int = 8

static var LAYER_BG: PackedInt32Array = PackedInt32Array([])
static var LAYER_DECO: PackedInt32Array = PackedInt32Array([])
static var LAYER_SOLID: PackedInt32Array = PackedInt32Array([])
static var LAYER_ABOVE: PackedInt32Array = PackedInt32Array([])

const PORTALS := [
	{
		"x": 0,
		"y": 7,
		"direction": "WEST",
		"target_map": "map_01",
		"spawn_x": 19,
		"spawn_y": 7
	}
]

const SPAWN := { "x": 10, "y": 7 }


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

