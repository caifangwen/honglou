extends Node

# === Supabase 配置 ===
const SUPABASE_URL = "https://daotqqwsxvydxqttmams.supabase.co"
const SUPABASE_ANON_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImRhb3RxcXdzeHZ5ZHhxdHRtYW1zIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMxNTg2NDYsImV4cCI6MjA4ODczNDY0Nn0.14c25wXFIAhoe1sJhdM7xJbEkJo3ihUqpu-VeXE680U"

# REST API 端点
const API_AUTH_SIGNUP   = SUPABASE_URL + "/auth/v1/signup"
const API_AUTH_LOGIN    = SUPABASE_URL + "/auth/v1/token?grant_type=password"
const API_AUTH_LOGOUT   = SUPABASE_URL + "/auth/v1/logout"
const API_PLAYERS       = SUPABASE_URL + "/rest/v1/players"
const API_GAMES         = SUPABASE_URL + "/rest/v1/games"

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

