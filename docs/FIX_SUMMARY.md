# 对食功能完善 - 最终修复总结

## 已完成的功能

### 1. 对食关系核心功能
- ✅ 发起对食/私约申请（UI 选择目标）
- ✅ 接受/拒绝申请
- ✅ 情报共享机制（对食关系自动共享情报）
- ✅ 双人挂机模式（触发率 +20%，情报碎片 +1）
- ✅ 背叛机制（详细后果说明、体面值下降、声名狼藉状态）
- ✅ 特殊事件系统（交换信物、私下幽会、分享秘密、维护搭档）
- ✅ 对食对话模板（问候、关怀、鼓励、警告、告别）

### 2. 数据库更新
- ✅ 新增 `maid_relationships.formed_at` - 关系建立时间
- ✅ 新增 `maid_relationships.shared_intel_ids` - 共享情报 ID 列表
- ✅ 新增 `maid_relationships.betrayer_uid` - 背叛者 ID
- ✅ 禁用所有表的行级安全（RLS）- 仅本地开发环境
- ✅ 授予 `anon` 角色所有表访问权限

### 3. 新增文件
- `features/relationship/DuiShiEvents.gd` - 对食事件系统
- `docs/DUISHI_FEATURE.md` - 对食功能说明文档
- `docs/LOCAL_SETUP_GUIDE.md` - 本地开发环境搭建指南
- `supabase/sql/00-local-roles.sql` - 创建 Supabase 兼容角色
- `supabase/sql/01-local-permissions.sql` - 授予本地开发权限
- `supabase/migrations/20260319_add_dui_shi_fields.sql` - 对食字段迁移
- `start-local-dev.bat` - 一键启动脚本
- `.env.local` - 本地模式配置文件

### 4. 配置更新
- `project.godot` - 注册 `DuiShiEvents` 为 Autoload
- `docker-compose.yml` - 修复 schema 路径，添加角色初始化
- `docker-compose.local-dev.yml` - 更新初始化脚本顺序
- `features/relationship/RelationshipPanel.gd` - 完善 UI 和交互
- `features/relationship/RelationshipManager.gd` - 添加核心逻辑
- `features/eavesdrop/EavesdropManager.gd` - 集成情报共享

## 本地环境启动步骤

### 方法一：使用启动脚本（推荐）
```powershell
.\start-local-dev.bat
```

### 方法二：手动启动
```powershell
# 1. 启动数据库环境
docker-compose -f docker-compose.local-dev.yml --project-name honglou up -d

# 2. 等待初始化（15 秒）
timeout /t 15 /nobreak

# 3. 重启 pgREST 加载 schema
docker-compose -f docker-compose.local-dev.yml --project-name honglou restart pgrest

# 4. 启动游戏
godot --use-local-db=true
```

## 测试对食功能

### 1. 登录游戏
- 选择 **袭人 (丫鬟)** 或 **晴雯 (丫鬟)** 快速登录

### 2. 建立对食关系
1. 打开角色信息页面
2. 在"我的关系"面板点击"发起对食/私约申请"
3. 选择"对食"类型
4. 选择另一个丫鬟角色
5. 发送申请

### 3. 接受申请
- 切换到另一个账号登录
- 在"待确认申请"列表中点击"接受"

### 4. 测试双人挂机
1. 进入"听壁脚"场景
2. 选择任意场景
3. 如果有对食关系，会显示双人挂机选项
4. 选择搭档并开始挂机

### 5. 测试情报共享
- 一个账号获得情报后
- 切换到另一个账号查看是否收到通知
- 检查关系面板中的共享情报数量

### 6. 测试背叛功能
1. 在关系面板点击"背叛搭档"
2. 查看详细后果说明
3. 输入确认文字"我已知晓后果"
4. 确认背叛
5. 检查是否获得情报副本

## 常见问题解决

### 问题 1：登录失败
**症状**：点击快速登录按钮后无响应或报错

**解决**：
```powershell
# 检查服务状态
docker ps

# 测试 API
curl "http://localhost:3000/players?select=id,character_name"

# 如果 API 无响应，重启 pgREST
docker-compose -f docker-compose.local-dev.yml restart pgrest
```

### 问题 2：挂机失败（401 错误）
**症状**：开始挂机时返回 401 错误

**解决**：
```powershell
# 重新授予权限
docker exec honglou_local_db psql -U postgres -d honglou -c "GRANT ALL ON ALL TABLES IN SCHEMA public TO anon;"

# 重启 pgREST
docker-compose -f docker-compose.local-dev.yml restart pgrest
```

### 问题 3：数据库初始化失败
**症状**：容器启动后立即停止，日志显示错误

**解决**：
```powershell
# 完全重建
docker-compose -f docker-compose.local-dev.yml down
rmdir /s /q local_db_data
docker-compose -f docker-compose.local-dev.yml up -d
```

## 服务访问信息

| 服务 | 地址 | 说明 |
|------|------|------|
| pgREST | http://localhost:3000 | REST API |
| pgAdmin | http://localhost:5050 | 数据库管理 |
| PostgreSQL | localhost:5432 | 数据库直连 |

**pgAdmin 登录**：
- 邮箱：admin@admin.com
- 密码：admin

## 下一步开发建议

1. **完善对食事件 UI** - 创建专门的事件弹窗显示对食事件
2. **添加关系进度** - 显示对食关系亲密度和成长系统
3. **扩展特殊事件** - 添加更多对食专属事件和剧情
4. **平衡数值** - 调整双人挂机奖励和背叛惩罚
5. **添加成就** - 为对食系统添加相关成就和统计
