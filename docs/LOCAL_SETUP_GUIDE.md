# 本地开发环境启动指南

## 前提条件
- Docker Desktop 已安装并运行
- Godot 4.x 已安装

## 启动步骤

### 1. 启动本地数据库环境

```powershell
# 在项目根目录执行
docker-compose -f docker-compose.local-dev.yml up -d
```

这将启动以下服务：
- **PostgreSQL** (端口 5432) - 数据库
- **pgREST** (端口 3000) - REST API 接口
- **pgAdmin** (端口 5050) - 数据库管理界面（可选访问）

### 2. 验证服务是否正常

```powershell
# 检查容器状态
docker ps

# 测试 pgREST API
curl "http://localhost:3000/players?select=id,character_name,role_class"
```

应该返回测试账号列表。

### 3. 启动游戏

#### 方法 A：使用 Godot 编辑器
1. 打开 Godot 编辑器
2. 加载项目
3. 按 F5 运行

#### 方法 B：命令行启动（带本地模式参数）
```powershell
godot --use-local-db=true
```

### 4. 登录游戏

1. 在游戏登录界面，点击快速登录按钮
2. 选择测试账号：
   - **袭人 (丫鬟)** - 推荐测试对食功能
   - **晴雯 (丫鬟)** - 推荐测试对食功能
   - 凤姐 (管家)
   - 贾宝玉 (主子)
   - 林黛玉 (主子)

## 常见问题

### 问题 1：登录失败，提示"本地模式"但无法查询玩家

**原因**：pgREST 服务未启动或权限不足

**解决**：
```powershell
# 重启 pgREST 容器
docker-compose -f docker-compose.local-dev.yml restart pgrest

# 授予数据库权限
docker exec honglou_local_db psql -U postgres -d honglou -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;"
```

### 问题 2：数据库初始化失败

**原因**：旧数据目录导致跳过初始化

**解决**：
```powershell
# 停止容器
docker-compose -f docker-compose.local-dev.yml down

# 删除旧数据目录
rmdir /s /q local_db_data

# 重新启动（会重新初始化）
docker-compose -f docker-compose.local-dev.yml up -d
```

### 问题 3：对食功能无法使用

**原因**：数据库缺少新字段

**解决**：
```powershell
# 执行迁移脚本
docker exec -i honglou_local_db psql -U postgres -d honglou < supabase/migrations/20260319_add_dui_shi_fields.sql
```

## 服务访问信息

| 服务 | 地址 | 说明 |
|------|------|------|
| pgREST | http://localhost:3000 | REST API 接口 |
| pgAdmin | http://localhost:5050 | 数据库管理界面 |
| PostgreSQL | localhost:5432 | 数据库直连端口 |

### pgAdmin 登录凭据
- 邮箱：admin@admin.com
- 密码：admin

### 测试账号

| 角色 | 邮箱 | 密码 | UID |
|------|------|------|-----|
| 凤姐 (管家) | fengjie@example.com | 123456 | 11111111-... |
| 袭人 (丫鬟) | xiren@example.com | 123456 | 44444444-... |
| 晴雯 (丫鬟) | qingwen@example.com | 123456 | 55555555-... |
| 贾宝玉 (主子) | baoyu@example.com | 123456 | 22222222-... |
| 林黛玉 (主子) | daiyu@example.com | 123456 | 33333333-... |

## 停止服务

```powershell
docker-compose -f docker-compose.local-dev.yml down
```

## 重置数据库

```powershell
# 停止并删除容器和数据
docker-compose -f docker-compose.local-dev.yml down
rmdir /s /q local_db_data

# 重新启动（会重新初始化）
docker-compose -f docker-compose.local-dev.yml up -d
```
