# 本地/云端数据库切换 - 完成总结

## ✅ 已完成的工作

### 1. 数据库配置

| 组件 | 状态 | 说明 |
|------|------|------|
| PostgreSQL | ✅ 运行中 | 端口 5432 |
| pgREST API | ✅ 运行中 | 端口 3000 |
| pgAdmin | ✅ 运行中 | 端口 5050 |

### 2. 代码修改

#### GameConfig.gd
- 添加本地/云端配置常量
- 添加 `_init_environment()` 动态初始化
- 支持三种切换方式：
  - `.env.local` 文件
  - 命令行参数 `--use-local-db`
  - 代码硬编码

#### SupabaseManager.gd
- 添加 `_is_local_mode` 标志
- 添加 `_check_local_mode()` 检测方法
- 添加 `_simulate_local_auth()` 模拟认证
- 本地模式跳过真实 HTTP 请求

#### Login.gd
- 添加 `_is_local_mode` 标志
- 测试账号添加固定 UID 映射
- 添加 `_simulate_local_login()` 本地登录
- `_on_auth_success()` 根据模式使用不同查询

### 3. 配置文件

#### docker-compose.local-dev.yml
```yaml
services:
  postgres:  # PostgreSQL 数据库
  pgrest:    # REST API 中间件
  pgadmin:   # 数据库管理界面
```

#### .env
```env
USE_LOCAL_DB=false  # 切换开关
LOCAL_API_BASE=http://localhost:3000
SUPABASE_URL=https://daotqqwsxvydxqttmams.supabase.co
```

### 4. 文档

| 文档 | 说明 |
|------|------|
| `本地云端切换指南.md` | 完整使用指南 |
| `Supabase 衔接说明.md` | Supabase CLI 使用 |
| `LOCAL_SETUP_SUMMARY.md` | 本文件 |

---

## 🚀 快速使用

### 启动本地环境

```powershell
# 启动所有服务（数据库 + HTTP API + pgAdmin）
docker-compose -p honglou -f docker-compose.local-dev.yml up -d

# 查看状态
docker-compose -p honglou ps
```

### 切换模式

**方法一：修改 .env.local**
```env
# 本地开发
USE_LOCAL_DB=true

# 云端部署
USE_LOCAL_DB=false
```

**方法二：命令行启动**
```powershell
# 本地模式
godot --use-local-db=true

# 云端模式
godot --use-local-db=false
```

### 访问服务

| 服务 | 地址 | 账号 |
|------|------|------|
| pgAdmin | http://localhost:5050 | admin@admin.com / admin |
| pgREST API | http://localhost:3000 | - |
| PostgreSQL | localhost:5432 | postgres / postgres123 |

---

## 📊 架构对比

### 本地模式
```
Godot → pgREST (3000) → PostgreSQL (5432)
         ↓
    模拟 Auth
```

### 云端模式
```
Godot → Supabase Cloud
         ↓
    Auth + Database + Realtime
```

---

## 🧪 测试账号（本地模式）

| 角色 | 邮箱 | UID |
|------|------|-----|
| 凤姐 | fengjie@example.com | 11111111-1111-1111-1111-111111111111 |
| 袭人 | xiren@example.com | 44444444-4444-4444-4444-444444444444 |
| 晴雯 | qingwen@example.com | 55555555-5555-5555-5555-555555555555 |

---

## ⚠️ 注意事项

### 本地模式限制
- ❌ 无真实用户认证（模拟）
- ❌ 无 RLS 行级安全
- ❌ 无 Realtime 实时更新
- ❌ 无 Storage 文件存储

### 推荐工作流
```
1. 本地开发 → USE_LOCAL_DB=true
2. 功能测试 → 本地 pgREST API
3. 推送云端 → supabase db push
4. 完整测试 → USE_LOCAL_DB=false
```

---

## 🔧 常用命令

```powershell
# 本地环境
docker-compose -p honglou -f docker-compose.local-dev.yml up -d
docker-compose -p honglou -f docker-compose.local-dev.yml down
docker-compose -p honglou logs -f

# 数据库命令行
docker exec -it honglou_local_db psql -U postgres -d honglou

# API 测试
curl http://localhost:3000/players?limit=5

# Supabase CLI
supabase login
supabase link --project-ref daotqqwsxvydxqttmams
supabase db push
```

---

## 📁 修改的文件

```
红楼回忆志/
├── scripts/
│   ├── data/
│   │   └── GameConfig.gd          # 已修改
│   ├── autoload/
│   │   └── SupabaseManager.gd     # 已修改
│   └── Login.gd                   # 已修改
├── docker-compose.local-dev.yml   # 新建
├── .env                           # 新建
├── supabase/
│   ├── config.toml                # 新建
│   └── migrations/                # 新建
└── *.md                           # 文档
```

---

## ✨ 下一步

1. **在 Godot 中测试**
   - 设置 `USE_LOCAL_DB=true`
   - 启动游戏
   - 点击快速登录测试

2. **推送到 Supabase**
   ```powershell
   supabase login
   supabase link --project-ref daotqqwsxvydxqttmams
   supabase db push
   ```

3. **云端测试**
   - 设置 `USE_LOCAL_DB=false`
   - 启动游戏测试完整功能

---

**完成时间**: 2026-03-15
**数据库版本**: PostgreSQL 15
**pgREST 版本**: latest
