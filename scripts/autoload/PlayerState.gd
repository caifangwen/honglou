extends Node

# 玩家本地状态，挂载为 Autoload

# 玩家基础属性
var uid: String = ""
var display_name: String = ""
var role_class: String = ""      # "steward" | "master" | "servant" | "elder" | "guest"
var character_name: String = ""  # 扮演的角色名（如"王熙凤"、"晴雯"）

# 新增字段
var player_db_id: String = ""    # players 表的 uuid（后续更新数据用）
var current_game_id: String = "" # 当前局 id

# 各阶层通用数值（根据角色阶层初始化不同值）
var stamina: int = 6           # 精力
var stamina_max: int = 6
var qi_shu: int = GameConfig.INIT_QI_SHU          # 气数（通用，上限200）
var silver: int = 0            # 银两（个人私产）
var face_value: int = GameConfig.INIT_FACE        # 体面值（上限100，低于20触发惩罚）
var prestige: int = GameConfig.INIT_PRESTIGE      # 名望值（主子专用，上限200）
var loyalty: int = GameConfig.INIT_LOYALTY        # 忠诚度（丫鬟专用，上限100）

# 精力恢复时间戳
var last_stamina_refresh: int = 0

signal stamina_changed(new_val: int)
signal silver_changed(new_val: int)
signal qi_shu_changed(new_val: int)

# 新增：从数据库返回的完整数据初始化 
func load_from_db(row: Dictionary) -> void: 
	player_db_id    = row.get("id", "") 
	display_name    = row.get("display_name", "") 
	character_name  = row.get("character_name", "") 
	current_game_id = row.get("current_game_id", "") 
	role_class      = row.get("role_class", "") 
	stamina         = row.get("stamina", 6) 
	stamina_max     = row.get("stamina_max", 6) 
	qi_shu          = row.get("qi_shu", 100) 
	silver          = row.get("silver", 0) 
	face_value      = row.get("face_value", 50) 
	prestige        = row.get("prestige", 10) 
	loyalty         = row.get("loyalty", 50) 
	initialize(role_class) 

func initialize(role: String) -> void:
	role_class = role
	match role:
		"steward":
			stamina_max = GameConfig.STAMINA_STEWARD
			stamina = GameConfig.STAMINA_STEWARD
		"servant":
			stamina_max = GameConfig.STAMINA_SERVANT
			stamina = GameConfig.STAMINA_SERVANT
		_:
			stamina_max = GameConfig.STAMINA_STEWARD
			stamina = GameConfig.STAMINA_STEWARD
	last_stamina_refresh = int(Time.get_unix_time_from_system())

func get_current_stamina() -> int:
	var elapsed: int = int(Time.get_unix_time_from_system()) - last_stamina_refresh
	var recovered: int = int(elapsed / GameConfig.STAMINA_RECOVERY_SEC)  # 每2小时恢复1点
	return min(stamina + recovered, stamina_max)

func consume_stamina(amount: int) -> bool:
	var current: int = get_current_stamina()
	if current < amount:
		return false
	stamina = current - amount
	last_stamina_refresh = int(Time.get_unix_time_from_system())
	stamina_changed.emit(stamina)
	return true
