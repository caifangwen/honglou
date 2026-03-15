extends Node

# === 环境配置 ===
# 可通过 .env 文件或 Godot 启动参数切换
# 启动参数示例：godot --use-local-db=true

# 云端 Supabase 配置（生产环境）
const SUPABASE_URL_CLOUD = "https://daotqqwsxvydxqttmams.supabase.co"
const SUPABASE_ANON_KEY_CLOUD = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhb3RxcXdzeHZ5ZHhxdHRtYW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNTg2NDYsImV4cCI6MjA4ODczNDY0Nn0.14c25wXFIAhoe1sJhdM7xJbEkJo3ihUqpu-VeXE680U"

# 本地数据库配置（开发环境）
const LOCAL_DB_HOST = "localhost"
const LOCAL_DB_PORT = "5432"
const LOCAL_DB_NAME = "honglou"
const LOCAL_DB_USER = "postgres"
const LOCAL_DB_PASSWORD = "postgres123"

# 运行时配置（根据环境动态设置）
var SUPABASE_URL: String = SUPABASE_URL_CLOUD
var SUPABASE_ANON_KEY: String = SUPABASE_ANON_KEY_CLOUD
var USE_LOCAL_DB: bool = false

# REST API 端点（动态生成）
var API_AUTH_SIGNUP: String
var API_AUTH_LOGIN: String
var API_AUTH_LOGOUT: String
var API_PLAYERS: String
var API_GAMES: String

# 本地数据库 HTTP 接口（如果使用 pgREST 或自定义中间件）
var LOCAL_API_BASE: String = "http://localhost:3000"


func _ready() -> void:
	_init_environment()
	_build_api_endpoints()


func _init_environment() -> void:
	# 1. 检查启动参数（Godot 4 正确方式）
	var cmdline_args = OS.get_cmdline_args()
	for arg in cmdline_args:
		if arg.begins_with("--use-local-db="):
			var val = arg.split("=")[1]
			USE_LOCAL_DB = val == "true" or val == "1"
			break
	
	# 2. 检查环境变量
	if OS.has_environment("USE_LOCAL_DB"):
		var env_val = OS.get_environment("USE_LOCAL_DB")
		USE_LOCAL_DB = env_val == "true" or env_val == "1"
	
	# 3. 检查 .env 文件（如果存在）
	if not USE_LOCAL_DB and FileAccess.file_exists("res://.env.local"):
		var file = FileAccess.open("res://.env.local", FileAccess.READ)
		if file:
			var content = file.get_as_text()
			if "USE_LOCAL_DB=true" in content or "USE_LOCAL_DB=1" in content:
				USE_LOCAL_DB = true
	
	# 4. 应用配置
	if USE_LOCAL_DB:
		print("[GameConfig] 使用本地数据库模式")
		SUPABASE_URL = LOCAL_API_BASE
		SUPABASE_ANON_KEY = "local-dev-key"
	else:
		print("[GameConfig] 使用云端 Supabase 模式")
		SUPABASE_URL = SUPABASE_URL_CLOUD
		SUPABASE_ANON_KEY = SUPABASE_ANON_KEY_CLOUD


func _build_api_endpoints() -> void:
	if USE_LOCAL_DB:
		# 本地模式：使用 pgREST HTTP 接口（直接表名，无 /rest/v1/ 前缀）
		API_AUTH_SIGNUP = LOCAL_API_BASE + "/auth/signup"  # 本地无 Auth，模拟
		API_AUTH_LOGIN = LOCAL_API_BASE + "/auth/login"   # 本地无 Auth，模拟
		API_AUTH_LOGOUT = LOCAL_API_BASE + "/auth/logout"
		API_PLAYERS = LOCAL_API_BASE + "/players"
		API_GAMES = LOCAL_API_BASE + "/games"
	else:
		# 云端模式：使用 Supabase API
		API_AUTH_SIGNUP = SUPABASE_URL + "/auth/v1/signup"
		API_AUTH_LOGIN = SUPABASE_URL + "/auth/v1/token?grant_type=password"
		API_AUTH_LOGOUT = SUPABASE_URL + "/auth/v1/logout"
		API_PLAYERS = SUPABASE_URL + "/rest/v1/players"
		API_GAMES = SUPABASE_URL + "/rest/v1/games"


# === 工具函数 ===

## 获取数据库连接信息（用于调试）
func get_db_info() -> Dictionary:
	if USE_LOCAL_DB:
		return {
			"mode": "local",
			"host": LOCAL_DB_HOST,
			"port": LOCAL_DB_PORT,
			"database": LOCAL_DB_NAME
		}
	else:
		return {
			"mode": "cloud",
			"project_ref": "daotqqwsxvydxqttmams",
			"url": SUPABASE_URL_CLOUD
		}

# === 精力系统 ===
const STAMINA_STEWARD: int = 6         # 管家精力上限
const STAMINA_SERVANT: int = 8         # 丫鬟/小厮精力上限
const STAMINA_RECOVERY_SEC: int = 7200 # 精力恢复间隔（秒）= 2小时

# === 行动精力消耗 ===
const COST_PROCURE: int = 1
const COST_ASSIGN_TASK: int = 1
const COST_SEARCH_GARDEN: int = 2
const COST_ADVANCE_PAYMENT: int = 1
const COST_SUPPRESS_RUMOR: int = 2
const COST_BLOCK_INFO: int = 3
const COST_PUBLISH_RUMOR: int = 5

# === 数值初始值 ===
const INIT_QI_SHU: int = 100
const MAX_QI_SHU: int = 200
const INIT_FACE: int = 50
const MAX_FACE: int = 100
const INIT_PRESTIGE: int = 10
const MAX_PRESTIGE: int = 200
const INIT_LOYALTY: int = 50

# === 流言发酵时间（毫秒）===
const RUMOR_STAGE_1_MS: int = 21600000  # 6小时
const RUMOR_STAGE_2_MS: int = 43200000  # 12小时

# === 亏空/内耗阈值 ===
const DEFICIT_CRISIS_THRESHOLD: float = 80.0
const CONFLICT_PURGE_THRESHOLD: float = 100.0
const AUDIT_THRESHOLD_MILD: float = 0.10
const AUDIT_THRESHOLD_SEVERE: float = 0.30

# === 管家系统额外常量 ===
const MAX_STEWARD_STAMINA: int = 6
const STEWARD_STAMINA_RECOVERY_HOURS: int = 2
const MIN_EMBEZZLEMENT_RISK_COUNT: int = 3
const AUDIT_DEADLINE_HOURS: int = 24
const ASSET_TRANSFER_WINDOW_HOURS: int = 2

# === 查账消耗 ===
const AUDIT_COST_QI_SHU: int = 20

# === 名望阈值（主子系统）===
const PRESTIGE_DOUBLE_SEARCH: int = 80
const PRESTIGE_JOINT_APPEAL: int = 120
const PRESTIGE_ELDER_ATTENTION: int = 150
const PRESTIGE_VULNERABLE: int = 20

# === 阶层字符串常量 ===
const CLASS_STEWARD: String = "管家"
const CLASS_MASTER: String = "主子"
const CLASS_SERVANT: String = "丫鬟"
const CLASS_ELDER: String = "元老"
const CLASS_GUEST: String = "清客"
