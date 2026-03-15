-- =====================================================
-- 诊断 RLS 权限问题
-- 在 Supabase SQL Editor 中运行
-- =====================================================

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

-- 4. 测试插入（模拟游戏场景）
-- 将下面的 UUID 替换为你的实际游戏 ID 和玩家 ID
-- INSERT INTO public.rumors (game_id, publisher_uid, target_uid, content, source_type, stage)
-- VALUES (
--     'your-game-id-here'::uuid,
--     'your-player-id-here'::uuid,
--     'target-player-id-here'::uuid,
--     '测试流言',
--     'freewrite',
--     1
-- );

-- 5. 如果策略不存在，运行以下修复脚本
-- （与 fix_rumors_permissions.sql 相同）
