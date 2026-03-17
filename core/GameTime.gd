extends Node

## 时间系统核心单例
## 负责游戏时间与现实时间的映射计算及同步

signal day_changed(new_day: int)
signal xun_changed(new_xun: int)
signal month_changed(new_month: int)
signal game_ended()
signal debug_speed_changed(multiplier: float)

# 时间常量（秒）
const SECONDS_PER_DAY: float = 7200.0
const SECONDS_PER_XUN: float = 72000.0
const SECONDS_PER_MONTH: float = 216000.0
const DAYS_PER_XUN: int = 10
const XUNS_PER_MONTH: int = 3

# 公开属性
var current_day: int = 1
var current_xun: int = 1
var current_month: int = 1
var day_progress: float = 0.0
var xun_progress: float = 0.0
var time_to_next_day: float = 0.0
var time_to_next_xun: float = 0.0

# 调试属性
@export var debug_speed_multiplier: float = 1.0:
	set(val):
		debug_speed_multiplier = val
		debug_speed_changed.emit(val)
@export var debug_epoch_offset: float = 0.0

# 内部状态
var _game_start_timestamp: int = 0
var _is_initialized: bool = false
var _current_game_id: String = ""

func _ready() -> void:
	# 默认使用当前时间作为起始点，直到从服务器加载
	_game_start_timestamp = int(Time.get_unix_time_from_system())
	_is_initialized = true

func _process(_delta: float) -> void:
	if not _is_initialized:
		return
	_update_time_logic()

## 从 Supabase 加载指定游戏局的起始时间
func load_game_data(game_id: String) -> void:
	_current_game_id = game_id
	# 假设 SupabaseManager 已在项目中配置好
	if has_node("/root/SupabaseManager"):
		var sm = get_node("/root/SupabaseManager")
		var result = await sm.db_get("/rest/v1/games?id=eq." + game_id + "&select=start_timestamp,speed_multiplier")
		if result["code"] == 200 and result["data"].size() > 0:
			var data = result["data"][0]
			_game_start_timestamp = data.get("start_timestamp", _game_start_timestamp)
			# 生产环境下通常 multiplier 为 1.0，但数据库可配置
			if OS.is_debug_build():
				debug_speed_multiplier = data.get("speed_multiplier", 1.0)
			print("[GameTime] 已同步游戏起始时间: ", _game_start_timestamp)

## 设置调试时间偏移量（手动跳跃时间）
func set_debug_epoch_offset(seconds: float) -> void:
	debug_epoch_offset = seconds
	_update_time_logic()

func _update_time_logic() -> void:
	var now = Time.get_unix_time_from_system()
	
	# 计算逻辑：(当前现实时间 - 起始现实时间 + 调试偏移) * 调试倍率
	var elapsed_real_seconds = (now - _game_start_timestamp) + debug_epoch_offset
	var game_seconds = elapsed_real_seconds * debug_speed_multiplier
	
	if game_seconds < 0: game_seconds = 0
	
	# 1. 计算当前维度（从1开始）
	var new_day = int(game_seconds / SECONDS_PER_DAY) + 1
	var new_xun = int(game_seconds / SECONDS_PER_XUN) + 1
	var new_month = int(game_seconds / SECONDS_PER_MONTH) + 1
	
	# 2. 计算进度 0.0 - 1.0
	day_progress = fmod(game_seconds, SECONDS_PER_DAY) / SECONDS_PER_DAY
	xun_progress = fmod(game_seconds, SECONDS_PER_XUN) / SECONDS_PER_XUN
	
	# 3. 计算剩余时间（现实秒数）
	if debug_speed_multiplier > 0:
		time_to_next_day = ((new_day * SECONDS_PER_DAY) - game_seconds) / debug_speed_multiplier
		time_to_next_xun = ((new_xun * SECONDS_PER_XUN) - game_seconds) / debug_speed_multiplier
	else:
		time_to_next_day = INF
		time_to_next_xun = INF
		
	# 4. 触发信号
	if new_day != current_day:
		current_day = new_day
		day_changed.emit(current_day)
		
	if new_xun != current_xun:
		current_xun = new_xun
		xun_changed.emit(current_xun)
		
	if new_month != current_month:
		current_month = new_month
		month_changed.emit(current_month)
	
	# 5. 检查游戏结束（假设15天结束，可根据实际业务调整）
	# if game_seconds >= 15 * SECONDS_PER_DAY * 10: # 15 游戏日
	#    game_ended.emit()
