extends Node2D

## 整个像素瓦片框架的入口节点

const Constants = preload("res://src/constants.gd")
const AssetStore = preload("res://src/assets.gd")
const Camera2DLite = preload("res://src/camera.gd")
const SceneManager = preload("res://src/scene.gd")
const TilemapRenderer = preload("res://src/tilemap.gd")
const PlayerCtrl = preload("res://src/player.gd")
const InputReader = preload("res://src/input.gd")

var assets: AssetStore
var scene_manager: SceneManager
var tilemap: TilemapRenderer
var player: PlayerCtrl
var input_reader: InputReader
var camera


func _ready() -> void:
	assets = AssetStore.new()
	add_child(assets)
	await assets.load_all()

	scene_manager = SceneManager.new()
	add_child(scene_manager)

	input_reader = InputReader.new()
	add_child(input_reader)

	var map_def: Dictionary = scene_manager.load_map("map_01")

	camera = Camera2DLite.new(
		get_viewport_rect().size.x,
		get_viewport_rect().size.y,
		map_def["cols"],
		map_def["rows"]
	)
	add_child(camera)
	set("camera", camera)
	set("input_reader", input_reader)

	tilemap = TilemapRenderer.new()
	add_child(tilemap)
	tilemap.setup(map_def, assets.get_image("world"))

	player = PlayerCtrl.new()
	add_child(player)
	player.setup(map_def)


func _process(_dt: float) -> void:
	# 仅负责请求重绘（逻辑在 _physics_process / 玩家脚本里）
	queue_redraw()
