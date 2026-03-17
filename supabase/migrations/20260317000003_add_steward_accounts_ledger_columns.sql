-- ============================================================
-- 修复 steward_accounts 表结构
-- 日期：2026-03-17
-- 问题：缺少 public_ledger 和 private_ledger 字段
-- ============================================================

-- 1. 添加账本字段
ALTER TABLE public.steward_accounts 
ADD COLUMN IF NOT EXISTS public_ledger jsonb DEFAULT '[]'::jsonb;

ALTER TABLE public.steward_accounts 
ADD COLUMN IF NOT EXISTS private_ledger jsonb DEFAULT '[]'::jsonb;

-- 2. 添加注释
COMMENT ON COLUMN public.steward_accounts.public_ledger IS '明账记录（JSONB 数组）';
COMMENT ON COLUMN public.steward_accounts.private_ledger IS '暗账记录（JSONB 数组）';
