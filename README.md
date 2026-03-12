# 红楼回忆志 - Supabase 配置说明

本项目使用 Supabase 作为后端服务。下面是本地开发时，如何配置 Supabase 相关信息的步骤。

## 环境变量

请在项目根目录创建一个 `.env.local`（或 `.env`）文件，并参考 `.env.example`：

```env
SUPABASE_PROJECT_REF=daotqqwsxvydxqttmams
SUPABASE_ACCESS_TOKEN=<从 Supabase 控制台获取的访问令牌>
```

> 注意：**不要**把真实的 `SUPABASE_ACCESS_TOKEN` 提交到 git 仓库。`.gitignore` 已经忽略所有 `.env*` 文件。

## 关联 Supabase 项目

首次在本机使用 Supabase CLI 时：

1. 在 PowerShell 中设置当前会话的访问令牌：

```powershell
$env:SUPABASE_ACCESS_TOKEN = "<你的 Supabase Access Token>"
```

2. 在项目根目录执行项目关联：

```powershell
supabase link --project-ref daotqqwsxvydxqttmams
```

这会在项目中的 `supabase/` 目录下生成/更新 Supabase 的本地配置文件（不包含访问令牌）。

## 推送本地数据库结构

当你更新了本地的数据库 schema 或 migrations 后，可以通过以下命令推送到远端 Supabase：

```powershell
supabase db push
```

在运行上述命令前，确保当前终端会话已经设置了 `SUPABASE_ACCESS_TOKEN` 环境变量。

