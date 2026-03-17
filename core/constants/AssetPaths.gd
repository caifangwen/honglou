extends Node

## 统一资源加载与访问

const ASSETS := {
	"tilesets": {
		"world": "res://assets/tileset_world.png",
		"indoor": "res://assets/tileset_indoor.png"
	},
	"sprites": {
		"player": "res://assets/player_sheet.png",
		"npc": "res://assets/npc_sheet.png"
	},
	"audio": {
		"bgm_field": "res://assets/audio/bgm_field.ogg",
		"sfx_step": "res://assets/audio/sfx_step.wav"
	}
}

var images: Dictionary = {}


func _ready() -> void:
	# 如果挂在场景中，可以在 _ready 即触发加载
	await load_all()


## 异步加载所有图片资源，返回自身以便链式调用
func load_all() -> Node:
	var tasks: Array[Signal] = []

	for category in ["tilesets", "sprites"]:
		for key in ASSETS[category].keys():
			var path: String = ASSETS[category][key]
			var tex: Resource = load(path)
			if tex:
				images[key] = tex

	return self


func get_image(key: String) -> Texture2D:
	var tex = images.get(key, null)
	if tex == null:
		# 尝试加载默认图标作为兜底
		tex = load("res://icon.svg")
	return tex

