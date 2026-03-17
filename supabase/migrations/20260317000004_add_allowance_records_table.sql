-- ============================================================
-- 添加 allowance_records 表
-- 日期：2026-03-17
-- 问题：缺失 allowance_records 表导致月例发放失败
-- ============================================================

-- 创建 allowance_records 表
CREATE TABLE IF NOT EXISTS public.allowance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    player_id uuid REFERENCES public.players(id),
    issued_by uuid REFERENCES public.players(id),
    amount_public int NOT NULL,
    amount_actual int NOT NULL,
    withheld_amount int DEFAULT 0,
    is_public boolean DEFAULT true,
    issued_at timestamptz DEFAULT now(),
    created_at timestamptz DEFAULT now()
);

-- 添加索引
CREATE INDEX IF NOT EXISTS idx_allowance_records_game ON public.allowance_records(game_id);
CREATE INDEX IF NOT EXISTS idx_allowance_records_player ON public.allowance_records(player_id);
CREATE INDEX IF NOT EXISTS idx_allowance_records_issued_by ON public.allowance_records(issued_by);

-- 添加注释
COMMENT ON TABLE public.allowance_records IS '月例发放记录表';
COMMENT ON COLUMN public.allowance_records.game_id IS '游戏局 ID';
COMMENT ON COLUMN public.allowance_records.player_id IS '领用人 ID';
COMMENT ON COLUMN public.allowance_records.issued_by IS '发放人 ID（管家）';
COMMENT ON COLUMN public.allowance_records.amount_public IS '名义金额（应发）';
COMMENT ON COLUMN public.allowance_records.amount_actual IS '实际金额（实发）';
COMMENT ON COLUMN public.allowance_records.withheld_amount IS '克扣金额';

-- 启用 RLS
ALTER TABLE public.allowance_records ENABLE ROW LEVEL SECURITY;

-- 添加 RLS 策略
DROP POLICY IF EXISTS "authenticated_select_allowance_records" ON public.allowance_records;
DROP POLICY IF EXISTS "authenticated_insert_allowance_records" ON public.allowance_records;

CREATE POLICY "authenticated_select_allowance_records" ON public.allowance_records
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_allowance_records" ON public.allowance_records
    FOR INSERT TO authenticated WITH CHECK (true);

-- 授予权限
GRANT ALL ON public.allowance_records TO authenticated;
GRANT ALL ON SEQUENCE public.allowance_records_id_seq TO authenticated;
