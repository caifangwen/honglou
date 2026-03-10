extends Node

# 全局游戏状态，挂载为 Autoload

# 游戏全局数值
var deficit_value: float = 0.0       # 家族亏空值 0-100%
var internal_conflict: float = 0.0   # 家族内耗值 0-100%
var current_day: int = 1             # 当前游戏日
var current_phase: String = "normal" # 当前阶段: normal/crisis/purge

# 信号：全局状态变化
signal deficit_changed(new_value: float)
signal conflict_changed(new_value: float)
signal special_event_triggered(event_name: String)
signal game_phase_changed(new_phase: String)

func update_deficit(delta: float) -> void:
    deficit_value = clamp(deficit_value + delta, 0.0, 100.0)
    deficit_changed.emit(deficit_value)
    _check_crisis_threshold()

func update_conflict(delta: float) -> void:
    internal_conflict = clamp(internal_conflict + delta, 0.0, 100.0)
    conflict_changed.emit(internal_conflict)
    _check_purge_threshold()

func _check_crisis_threshold() -> void:
    # 亏空超过80%，财政危机
    if deficit_value >= 80.0 and current_phase == "normal":
        current_phase = "crisis"
        game_phase_changed.emit("crisis")

func _check_purge_threshold() -> void:
    # 内耗达到100%，触发抄家
    if internal_conflict >= 100.0:
        special_event_triggered.emit("抄检大观园")
        current_phase = "purge"
        game_phase_changed.emit("purge")

