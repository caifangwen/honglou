extends Node

enum PlayerState {
	IDLE,
	WALK,
	RUN,
	CLIMB,
	SWIM,
	DEAD
}


## 根据输入与特殊瓦片更新玩家状态
## player 需有字段：state: int
static func update_player_state(player: Object, input: Dictionary, special_tile: String) -> void:
	var prev: int = player.state

	match player.state:
		PlayerState.IDLE:
			if input.get("moving", false):
				player.state = PlayerState.WALK
			if special_tile == "LADDER" and input.get("up", false):
				player.state = PlayerState.CLIMB
			if special_tile == "WATER":
				player.state = PlayerState.SWIM

		PlayerState.WALK:
			if not input.get("moving", false):
				player.state = PlayerState.IDLE
			if special_tile == "LADDER" and input.get("up", false):
				player.state = PlayerState.CLIMB
			if special_tile == "WATER":
				player.state = PlayerState.SWIM

		PlayerState.CLIMB:
			if not (input.get("up", false) or input.get("down", false) or input.get("moving", false)):
				player.state = PlayerState.IDLE
			if special_tile != "LADDER":
				player.state = PlayerState.IDLE

		PlayerState.SWIM:
			if special_tile != "WATER":
				player.state = PlayerState.IDLE

		PlayerState.DEAD:
			# 死亡状态下暂不自动恢复
			pass

	if player.state != prev:
		player.anim_frame = 0
		player.anim_timer = 0.0

