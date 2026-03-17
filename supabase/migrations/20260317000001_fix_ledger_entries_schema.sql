-- ============================================================
-- 修复 ledger_entries 表结构
-- 日期：2026-03-17
-- 问题：Edge Function 中插入的字段与数据库表结构不匹配
-- ============================================================

-- 1. 添加缺失的字段
ALTER TABLE public.ledger_entries 
ADD COLUMN IF NOT EXISTS treasury_id uuid REFERENCES public.treasury(game_id);

ALTER TABLE public.ledger_entries 
ADD COLUMN IF NOT EXISTS ledger_type text DEFAULT 'public' CHECK (ledger_type IN ('public', 'private'));

ALTER TABLE public.ledger_entries 
ADD COLUMN IF NOT EXISTS entry_type text DEFAULT 'allocation' CHECK (entry_type IN ('allocation', 'procurement', 'advance', 'other'));

ALTER TABLE public.ledger_entries 
ADD COLUMN IF NOT EXISTS note text;

-- 2. 移除不再需要的字段
ALTER TABLE public.ledger_entries 
DROP COLUMN IF EXISTS action_type;

ALTER TABLE public.ledger_entries 
DROP COLUMN IF EXISTS approval_status;

-- 3. 添加索引以提高查询性能
CREATE INDEX IF NOT EXISTS idx_ledger_entries_game ON public.ledger_entries(game_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_treasury ON public.ledger_entries(treasury_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_actor ON public.ledger_entries(actor_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_target ON public.ledger_entries(target_id);
CREATE INDEX IF NOT EXISTS idx_ledger_entries_created_at ON public.ledger_entries(created_at);

-- 4. 添加注释
COMMENT ON COLUMN public.ledger_entries.treasury_id IS '关联的银库 ID';
COMMENT ON COLUMN public.ledger_entries.ledger_type IS '账本类型：public(明账), private(暗账)';
COMMENT ON COLUMN public.ledger_entries.entry_type IS '条目类型：allocation(发放), procurement(采办), advance(预支), other(其他)';
COMMENT ON COLUMN public.ledger_entries.note IS '备注说明';

-- 5. 启用 RLS
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;

-- 6. 添加 RLS 策略
DROP POLICY IF EXISTS "authenticated_select_ledger_entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "authenticated_insert_ledger_entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "authenticated_update_ledger_entries" ON public.ledger_entries;

CREATE POLICY "authenticated_select_ledger_entries" ON public.ledger_entries
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_ledger_entries" ON public.ledger_entries
    FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_ledger_entries" ON public.ledger_entries
    FOR UPDATE TO authenticated USING (true);

-- 7. 授予权限
GRANT ALL ON public.ledger_entries TO authenticated;
GRANT ALL ON SEQUENCE public.ledger_entries_id_seq TO authenticated;
