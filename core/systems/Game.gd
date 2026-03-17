extends Node2D

## 整个像素瓦片框架的入口节点

const GameConstants = preload("res://core/constants/GameConstants.gd")
const AssetPaths = preload("res://core/constants/AssetPaths.gd")
const CameraLite = preload("res://core/systems/Camera.gd")
const Scene = preload("res://core/systems/Scene.gd")
const TilemapRenderer = preload("res://core/systems/TileMap.gd")
const Player = preload("res://core/systems/Player.gd")
const InputHandler = preload("res://core/systems/InputHandler.gd")

var assets: AssetPaths
var scene_manager: Scene
var tilemap: TilemapRenderer
var player: Player
var input_reader: InputHandler
var camera: CameraLite


func _ready() -> void:
	assets = AssetPaths.new()
	add_child(assets)
	await assets.load_all()

	scene_manager = Scene.new()
	add_child(scene_manager)

	input_reader = InputHandler.new()
	add_child(input_reader)

	var map_def: Dictionary = scene_manager.load_map("map_01")

	camera = CameraLite.new(
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

	player = Player.new()
	add_child(player)
	player.setup(map_def)


func _process(_dt: float) -> void:
	# 仅负责请求重绘（逻辑在 _physics_process / 玩家脚本里）
	queue_redraw()
