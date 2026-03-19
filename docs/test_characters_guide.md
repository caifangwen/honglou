# 测试角色快速导入与登录指南

## 更新日期
2026-03-19

---

## 一、快速导入测试角色到数据库

### 方法 A：使用 Supabase SQL Editor（推荐）

1. 打开 Supabase 控制台，进入 SQL Editor
2. 复制并执行 `supabase/sql/import_test_characters.sql` 文件中的全部 SQL 代码
3. 执行成功后，会显示已导入的角色列表

### 方法 B：使用命令行

```bash
# 如果使用本地 Supabase
supabase db reset  # 重置本地数据库
supabase db push   # 推送最新 schema

# 然后手动执行 import_test_characters.sql
```

### 方法 C：使用 seed.sql

`supabase/sql/seed.sql` 已包含完整的测试数据，在项目初始化时会自动执行。

---

## 二、测试角色列表

### 管家（2 人）
| 角色名 | 邮箱 | 密码 | UID |
|--------|------|------|-----|
| 🔸 王熙凤 | fengjie@example.com | 123456 | 11111111-... |
| 🔸 平儿 | pingr@example.com | 123456 | aaaaaaaa-... |

### 主子（6 人）
| 角色名 | 邮箱 | 密码 |
|--------|------|------|
| 👑 贾宝玉 | baoyu@example.com | 123456 |
| 👑 林黛玉 | daiyu@example.com | 123456 |
| 👑 薛宝钗 | baochai@example.com | 123456 |
| 👑 贾迎春 | yingchun@example.com | 123456 |
| 👑 贾探春 | tanchun@example.com | 123456 |
| 👑 贾惜春 | xichun@example.com | 123456 |

### 丫鬟（5 人）
| 角色名 | 邮箱 | 密码 |
|--------|------|------|
| 🌸 袭人 | xiren@example.com | 123456 |
| 🌸 晴雯 | qingwen@example.com | 123456 |
| 🌸 鸳鸯 | yuanyang@example.com | 123456 |
| 🌸 紫鹃 | zijuan@example.com | 123456 |
| 🌸 麝月 | mili@example.com | 123456 |

### 小厮（2 人）
| 角色名 | 邮箱 | 密码 |
|--------|------|------|
| 📦 茗烟 | mingyan@example.com | 123456 |
| 📦 兴儿 | xingr@example.com | 123456 |

---

## 三、使用快捷登录

### 步骤：
1. 启动游戏，进入登录界面
2. 在"快捷登录测试账号"区域，点击任意角色按钮
3. 系统会自动登录并加载对应角色数据
4. 如果是首次登录，会自动创建角色并进入游戏

### 本地模式 vs 云端模式
- **本地模式**：使用预设的固定 UID 映射，无需联网
- **云端模式**：需要真实的 Supabase 账号体系

---

## 四、差事分配系统使用指南

### 如何使用差事分派功能：

1. **进入银库界面**
   - 从主界面进入"银库"（Treasury）

2. **点击差使分派按钮**
   - 在行动面板点击"差使分派（精力 -1）"

3. **选择差事类型**
   - 跑腿差事：精力消耗 1，赏银 5，目标精力 -2
   - 看守差事：精力消耗 1，赏银 8，目标精力 -1
   - 采办差事：精力消耗 1，赏银 10，目标精力 -3
   - 传话差事：精力消耗 1，赏银 6，目标精力 -2
   - 打扫差事：精力消耗 1，赏银 4，目标精力 -2
   - 特殊差事：精力消耗 2，赏银 15，目标精力 -4

4. **选择目标玩家**
   - 从下拉列表中选择要分派差事的玩家
   - 显示玩家名称和角色类型（主子/丫鬟/小厮）

5. **设置赏银**
   - 使用 SpinBox 调整赏银数额
   - 范围为基准值的 1-3 倍

6. **确认分派**
   - 点击"确认分派"执行
   - 系统自动扣除管家精力
   - 目标玩家获得银两，精力减少
   - 发送消息通知目标玩家

---

## 五、常见问题

### Q1: 快捷登录按钮不显示？
**A:** 检查 Login.tscn 中的 QuickLoginScroll 节点是否正确配置，确保内部有 VBoxContainer。

### Q2: 登录提示"角色已存在"？
**A:** 执行 `import_test_characters.sql` 清理旧数据后重试。

### Q3: 差事分派失败？
**A:** 
- 检查是否有足够精力
- 确认目标玩家已选择
- 查看控制台错误日志

### Q4: 数据库连接失败？
**A:** 
- 本地模式：确保 `.env.local` 配置正确
- 云端模式：检查 Supabase 项目状态

---

## 六、文件清单

本次更新涉及的文件：

```
scenes/main/Login.gd              - 登录逻辑（已更新测试账号列表）
scenes/main/Login.tscn            - 登录界面（已添加快捷登录滚动区域）
features/treasury/TreasuryUI.gd   - 银库 UI（已添加差事分派面板）
features/treasury/Treasury.tscn   - 银库场景（已添加差事分派 UI）
supabase/sql/seed.sql             - 种子数据（已更新测试角色）
supabase/sql/import_test_characters.sql - 快速导入脚本（新增）
supabase/migrations/20260319_add_task_types.sql - 差事类型迁移（新增）
supabase/sql/full_schema.sql      - 完整架构（已更新 RPC 函数）
docs/changelog_task_system.md     - 差事系统更新日志
docs/test_characters_guide.md     - 本文件
```

---

## 七、下一步建议

1. **测试差事系统**
   - 登录王熙凤账号
   - 进入银库，尝试分派不同类型的差事
   - 切换到被分派的账号查看消息和银两变化

2. **验证登录流程**
   - 测试所有快捷登录按钮
   - 验证新账号自动创建功能
   - 检查角色属性是否正确加载

3. **数据持久化**
   - 执行数据库备份
   - 验证数据同步功能
