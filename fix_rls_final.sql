-- ============================================================
-- 最终 RLS 权限修复脚本
-- 在 Supabase SQL Editor 中运行此脚本
-- ============================================================

-- 1. 首先诊断当前状态
SELECT '=== 当前 RLS 状态 ===' AS info;
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' AND tablename='rumors';

SELECT '=== 当前 rumors 表策略 ===' AS info;
SELECT policyname, cmd, roles, qual, with_check FROM pg_policies WHERE tablename='rumors';

-- 2. 强制删除所有可能的旧策略
DO $$
BEGIN
    EXECUTE 'DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "authenticated_delete_rumors" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "Enable read access for all authenticated users" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "Enable update for authenticated users" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "Users can view own rumors" ON public.rumors';
    EXECUTE 'DROP POLICY IF EXISTS "Users can insert own rumors" ON public.rumors';
END $$;

-- 3. 禁用再启用 RLS（强制刷新）
ALTER TABLE public.rumors DISABLE ROW LEVEL SECURITY;
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;

-- 4. 创建新的宽松策略
CREATE POLICY "authenticated_select_rumors" ON public.rumors
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "authenticated_insert_rumors" ON public.rumors
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "authenticated_update_rumors" ON public.rumors
FOR UPDATE TO authenticated
USING (true);

-- 5. 验证策略已创建
SELECT '=== 修复后的策略 ===' AS info;
SELECT policyname, cmd, roles FROM pg_policies WHERE tablename='rumors';

-- 6. 同样修复 players 表（用于创建玩家数据）
ALTER TABLE public.players ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_insert_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_update_players" ON public.players;

CREATE POLICY "authenticated_select_players" ON public.players FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_players" ON public.players FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_players" ON public.players FOR UPDATE TO authenticated USING (true);

SELECT '=== players 表策略 ===' AS info;
SELECT policyname, cmd, roles FROM pg_policies WHERE tablename='players';

-- 7. 完成
SELECT 'RLS 权限修复完成！请重启游戏测试。' AS result;
