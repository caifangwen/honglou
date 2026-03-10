extends Node

## 键盘输入状态
var _keys: Dictionary = {}

const KEYBINDS := {
	"up":     ["Up", "W"],
	"down":   ["Down", "S"],
	"left":   ["Left", "A"],
	"right":  ["Right", "D"],
	"run":    ["Shift"],
	"action": ["Space", "Z"],
	"debug":  ["F1"]
}


func _ready() -> void:
	set_process_input(true)


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var ev := event as InputEventKey
		var sc := OS.get_keycode_string(ev.keycode)
		if ev.pressed:
			_keys[sc] = true
		else:
			_keys[sc] = false


func _pressed(name: String) -> bool:
	if not KEYBINDS.has(name):
		return false
	for sc in KEYBINDS[name]:
		if _keys.get(sc, false):
			return true
	return false


## 读取当前帧输入
func read_input() -> Dictionary:
	var left: bool = _pressed("left")
	var right: bool = _pressed("right")
	var up: bool = _pressed("up")
	var down: bool = _pressed("down")

	var dx: int = (1 if right else 0) - (1 if left else 0)
	var dy: int = (1 if down else 0) - (1 if up else 0)

	return {
		"left": left,
		"right": right,
		"up": up,
		"down": down,
		"run": _pressed("run"),
		"action": _pressed("action"),
		"moving": left or right or up or down,
		"dx": float(dx),
		"dy": float(dy)
	}

