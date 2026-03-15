# Supabase 衔接说明

本文档说明如何在本地开发和 Supabase 云端之间切换。

---

## 📋 目录

1. [首次设置](#首次设置)
2. [本地开发](#本地开发)
3. [推送到 Supabase](#推送到-supabase)
4. [Godot 代码切换](#godot-代码切换)

---

## 首次设置

### 1. 安装 Supabase CLI

```powershell
# 方法一：使用 winget（推荐）
winget install supabase.cli

# 方法二：使用 npm
npm install -g supabase
```

### 2. 登录 Supabase

```powershell
supabase login
```

这会打开浏览器，登录成功后会自动配置 access token。

### 3. 关联项目

```powershell
cd "C:\Users\Frida\红楼回忆志"
supabase link --project-ref daotqqwsxvydxqttmams
```

关联成功后会生成 `supabase/config.toml` 文件。

---

## 本地开发

### 启动本地数据库

```powershell
# 启动 PostgreSQL 和 pgAdmin
docker-compose up -d

# 查看日志
docker-compose logs -f postgres
```

### 访问本地数据库

- **pgAdmin**: http://localhost:5050
  - 邮箱：`admin@admin.com`
  - 密码：`admin`

- **直连参数**:
  - Host: `localhost`
  - Port: `5432`
  - Database: `honglou`
  - User: `postgres`
  - Password: `postgres123`

### 本地开发限制

本地 PostgreSQL 与 Supabase 的区别：

| 功能 | 本地 PostgreSQL | Supabase 云端 |
|------|----------------|--------------|
| Auth 系统 | ❌ 无 `auth.users` 表 | ✅ 完整 Auth |
| RLS 行级安全 | ❌ 跳过 | ✅ 启用 |
| Realtime | ❌ 无 WebSocket | ✅ 完整支持 |
| Storage | ❌ 无 | ✅ 文件存储 |

**影响**：本地开发时无法测试登录注册、实时更新功能。

---

## 推送到 Supabase

### 推送数据库结构

```powershell
# 推送所有 migrations 到云端
supabase db push
```

### 查看云端数据库状态

```powershell
# 查看已应用的 migrations
supabase migration list
```

### 从云端拉取最新结构

```powershell
# 如果云端有变更，可以拉取到本地
supabase db pull
```

---

## Godot 代码切换

### 方法一：修改 GameConfig.gd（简单）

在 `scripts/data/GameConfig.gd` 中修改：

```gdscript
# 本地开发
const SUPABASE_URL = "http://localhost:5432"  # 不适用，本地用直连

# 云端部署
const SUPABASE_URL = "https://daotqqwsxvydxqttmams.supabase.co"
```

### 方法二：使用环境变量（推荐）

创建 `.env.local` 文件（不被 git 追踪）：

```env
SUPABASE_URL=https://daotqqwsxvydxqttmams.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
USE_LOCAL_DB=false
```

在 Godot 中读取：

```gdscript
# 在 autoload 脚本中
func _ready():
    if OS.has_environment("USE_LOCAL_DB"):
        var use_local = OS.get_environment("USE_LOCAL_DB")
        if use_local == "true":
            # 切换到本地数据库配置
            GameConfig.SUPABASE_URL = "http://localhost:5432"
```

### 方法三：构建时切换

```powershell
# 本地开发构建
godot --build-debug

# 生产环境构建（使用云端 Supabase）
godot --build-release
```

---

## 常见问题

### Q1: 本地开发如何测试登录功能？

本地 PostgreSQL 没有 `auth.users` 表，有两种方案：

1. **跳过 Auth**：在代码中检测本地环境，直接创建 `public.players` 记录
2. **使用 Supabase 测试账号**：本地开发也连接云端 Supabase Auth

### Q2: 如何同步本地和云端数据？

```powershell
# 导出本地数据
docker exec honglou_local_db pg_dump -U postgres honglou > local_backup.sql

# 导入到云端（谨慎操作！）
# 需要手动在 Supabase SQL Editor 中执行
```

### Q3: Realtime 本地能测试吗？

不能。本地 PostgreSQL 没有 Supabase Realtime 功能。
建议：本地测试基础功能，Realtime 留到云端测试。

---

## 推荐工作流

```
1. 本地开发新功能 → docker-compose up -d
2. 测试通过 → 更新 schema.sql
3. 推送到云端 → supabase db push
4. 云端测试 → 修改 Godot 配置连接云端
5. 发布版本
```

---

## 快速命令参考

```powershell
# 本地数据库
docker-compose up -d              # 启动
docker-compose down               # 停止
docker-compose logs -f            # 查看日志

# Supabase CLI
supabase login                    # 登录
supabase link --project-ref xxx   # 关联项目
supabase db push                  # 推送数据库
supabase migration list           # 查看 migrations
```
