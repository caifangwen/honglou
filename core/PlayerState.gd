extends Node

# 玩家本地状态，挂载为 Autoload

# 玩家基础属性
var uid: String = ""
var display_name: String = ""
var username: String = ""
var role_class: String = ""      # "steward" | "master" | "servant" | "elder" | "guest"
var character_name: String = ""  # 扮演的角色名（如"王熙凤"、"晴雯"）

# 新增字段
var player_db_id: String = ""    # players 表的 uuid（后续更新数据用）
var current_game_id: String = "" # 当前局 id

# 各阶层通用数值（根据角色阶层初始化不同值）
var stamina: int = 6:
	set(val):
		if stamina != val:
			stamina = val
			# 更新基础值时重置刷新时间，以当前时间为准
			last_stamina_refresh = int(Time.get_unix_time_from_system())
			stamina_changed.emit(stamina)
var stamina_max: int = 6
var qi_shu: int = GameConfig.INIT_QI_SHU:
	set(val):
		qi_shu = val
		qi_shu_changed.emit(qi_shu)
var silver: int = 0:
	set(val):
		silver = val
		silver_changed.emit(silver)
var face_value: int = GameConfig.INIT_FACE        # 体面值（上限 100，低于 20 触发惩罚）
var prestige: int = GameConfig.INIT_PRESTIGE:      # 名望值（主子专用，上限 200）
	set(val):
		prestige = val
		prestige_changed.emit(prestige)
var loyalty: int = GameConfig.INIT_LOYALTY        # 忠诚度（丫鬟专用，上限 100）

# 精力恢复时间戳
var last_stamina_refresh: int = 0

signal stamina_changed(new_val: int)
signal silver_changed(new_val: int)
signal qi_shu_changed(new_val: int)
signal prestige_changed(new_val: int)

# 新增：从数据库返回的完整数据初始化
func load_from_db(row: Dictionary) -> void:
	# 先执行基础初始化，再用数据库数据覆盖
	initialize(_safe_get(row, "role_class", ""))

	player_db_id    = _safe_get(row, "id", "")
	display_name    = _safe_get(row, "display_name", "")
	username        = _safe_get(row, "username", "")
	character_name  = _safe_get(row, "character_name", "")
	current_game_id = _safe_get(row, "current_game_id", "")
	stamina         = _safe_get(row, "stamina", stamina)
	stamina_max     = _safe_get(row, "stamina_max", stamina_max)
	
	# 处理精力刷新时间
	var refreshed_at = _safe_get(row, "stamina_refreshed_at", "")
	if refreshed_at != "":
		last_stamina_refresh = _parse_iso_timestamp(refreshed_at)
	else:
		last_stamina_refresh = int(Time.get_unix_time_from_system())
		
	qi_shu          = _safe_get(row, "qi_points", qi_shu)
	silver          = _safe_get(row, "silver", silver)
	face_value      = _safe_get(row, "face_value", face_value)
	prestige        = _safe_get(row, "prestige", prestige)
	loyalty         = _safe_get(row, "loyalty", loyalty)

func _safe_get(dict: Dictionary, key: String, default: Variant) -> Variant:
	var val: Variant = dict.get(key)
	return val if val != null else default

func _parse_iso_timestamp(iso_str: String) -> int:
	if iso_str == "": 
		return int(Time.get_unix_time_from_system())
	# 处理常见格式，去掉 T、Z、+ 等干扰
	var clean = iso_str.replace("T", " ").split("+")[0].split("Z")[0]
	return int(Time.get_unix_time_from_datetime_string(clean))

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
	var recovered: int = int(elapsed / GameConfig.STAMINA_RECOVERY_SEC)  # 每 2 小时恢复 1 点
	return mini(stamina + recovered, stamina_max)

func consume_stamina(amount: int) -> bool:
	var current: int = get_current_stamina()
	if current < amount:
		return false
	# 设置 stamina 会触发 setter 自动更新 last_stamina_refresh 和发出信号
	stamina = current - amount
	# 消耗精力后同步到数据库
	sync_to_db()
	return true

func sync_to_db() -> void:
	if player_db_id == "": 
		print("[PlayerState] player_db_id is empty, skipping sync")
		return
	
	var data = {
		"stamina": stamina,
		"stamina_refreshed_at": Time.get_datetime_string_from_system(false, true),
		"qi_points": qi_shu,
		"silver": silver,
		"prestige": prestige,
		"loyalty": loyalty,
		"face_value": face_value
	}
	
	print("[PlayerState] Syncing to DB: ", data)
	# 使用 db_update 而不是 update_into_table，因为 db_update 处理了 rest/v1 前缀
	var res = await SupabaseManager.db_update("players", "id=eq." + player_db_id, data)
	if res["code"] != 200:
		push_error("[PlayerState] Sync to DB failed: " + str(res.get("error", "unknown")))
	else:
		print("[PlayerState] Sync to DB successful")
