-- ============================================================
-- 诊断 RLS 权限问题
-- 在 Supabase SQL Editor 中运行此脚本
-- ============================================================

-- 1. 检查当前用户
SELECT auth.uid() AS current_user_id;

-- 2. 检查 rumors 表的 RLS 状态
SELECT 
    tablename,
    rowsecurity AS rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename = 'rumors';

-- 3. 检查 rumors 表的所有策略
SELECT 
    policyname,
    cmd,
    roles,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'rumors';

-- 4. 检查 players 表是否有数据
SELECT id, auth_uid, username, role_class FROM public.players LIMIT 5;

-- 5. 检查 games 表是否有数据
SELECT id, status FROM public.games LIMIT 5;

-- 6. 测试：尝试以当前用户身份插入一条测试流言
-- （请替换下面的 UUID 为你的实际玩家 ID 和游戏 ID）
-- SELECT 
--     id AS my_player_id,
--     auth_uid AS my_auth_uid,
--     current_game_id AS my_game_id
-- FROM public.players 
-- WHERE auth_uid = auth.uid();

-- 7. 检查 RLS 策略是否阻止了插入
-- 运行以下查询查看是否有匹配的策略
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    roles,
    CASE 
        WHEN cmd = 'INSERT' THEN 'INSERT policy exists'
        WHEN cmd = 'SELECT' THEN 'SELECT policy exists'
        WHEN cmd = 'UPDATE' THEN 'UPDATE policy exists'
        ELSE 'Other'
    END AS policy_type
FROM pg_policies
WHERE tablename = 'rumors';

-- 8. 强制修复：删除所有旧策略并重新创建
DO $$
BEGIN
    -- 删除旧策略
    DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
    DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;
    DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;
    DROP POLICY IF EXISTS "authenticated_delete_rumors" ON public.rumors;
    
    -- 启用 RLS
    ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;
    
    -- 创建新策略 - 允许所有认证用户操作
    CREATE POLICY "authenticated_insert_rumors" ON public.rumors 
    FOR INSERT TO authenticated 
    WITH CHECK (true);
    
    CREATE POLICY "authenticated_select_rumors" ON public.rumors 
    FOR SELECT TO authenticated 
    USING (true);
    
    CREATE POLICY "authenticated_update_rumors" ON public.rumors 
    FOR UPDATE TO authenticated 
    USING (true);
    
    RAISE NOTICE 'RLS 策略已修复';
END $$;

-- 9. 验证策略已创建
SELECT policyname, cmd, roles FROM pg_policies WHERE tablename = 'rumors';
