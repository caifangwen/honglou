extends Node

const PlayerStateDef = preload("res://src/player_states.gd")
const Constants = preload("res://src/constants.gd")

## 动画定义
const ANIMATIONS: Dictionary = {
	"idle_down":  {"row": 0, "frames": 2, "fps": 4.0, "loop": true},
	"idle_up":    {"row": 1, "frames": 2, "fps": 4.0, "loop": true},
	"idle_side":  {"row": 2, "frames": 2, "fps": 4.0, "loop": true},
	"walk_down":  {"row": 3, "frames": 4, "fps": 8.0, "loop": true},
	"walk_up":    {"row": 4, "frames": 4, "fps": 8.0, "loop": true},
	"walk_side":  {"row": 5, "frames": 4, "fps": 8.0, "loop": true},
	"climb":      {"row": 6, "frames": 2, "fps": 6.0, "loop": true},
	"swim":       {"row": 7, "frames": 4, "fps": 6.0, "loop": true},
	"dead":       {"row": 8, "frames": 5, "fps": 8.0, "loop": false}
}


## 根据玩家状态和朝向选择动画 key
static func get_animation_key(state: int, facing: String) -> String:
	match state:
		PlayerStateDef.PlayerState.IDLE:
			return "idle_%s" % facing
		PlayerStateDef.PlayerState.WALK, PlayerStateDef.PlayerState.RUN:
			return "walk_%s" % facing
		PlayerStateDef.PlayerState.CLIMB:
			return "climb"
		PlayerStateDef.PlayerState.SWIM:
			return "swim"
		PlayerStateDef.PlayerState.DEAD:
			return "dead"
	return "idle_down"


## 更新动画帧（与帧率解耦）
## player 需有：state:int, facing:String, anim_frame:int, anim_timer:float
static func update_animation(player: Object, dt: float) -> void:
	var anim_key: String = get_animation_key(player.state, player.facing)
	var anim: Dictionary = ANIMATIONS.get(anim_key, ANIMATIONS["idle_down"])

	player.anim_timer += dt
	var frame_duration: float = 1.0 / float(anim["fps"])

	if player.anim_timer >= frame_duration:
		player.anim_timer -= frame_duration
		player.anim_frame += 1
		if player.anim_frame >= int(anim["frames"]):
			if anim["loop"]:
				player.anim_frame = 0
			else:
				player.anim_frame = int(anim["frames"]) - 1

