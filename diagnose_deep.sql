-- ============================================================
-- 深度诊断 RLS 问题
-- 在 Supabase SQL Editor 中运行
-- ============================================================

-- 1. 检查当前认证用户
SELECT 
    auth.uid() AS current_auth_uid,
    current_setting('request.jwt.claims', true)::json->>'sub' AS jwt_sub;

-- 2. 检查 players 表中是否有对应 auth_uid 的记录
SELECT 
    id AS player_id,
    auth_uid,
    username,
    role_class,
    current_game_id
FROM public.players
WHERE auth_uid = auth.uid();

-- 3. 检查 games 表是否有目标游戏
SELECT id, status FROM public.games WHERE id = '00000000-0000-0000-0000-000000000001';

-- 4. 检查目标玩家是否存在
SELECT id, username, role_class FROM public.players WHERE id = '55555555-5555-5555-5555-555555555555';

-- 5. 手动测试插入（使用当前认证用户）
DO $$
DECLARE
    v_player_id uuid;
    v_target_id uuid;
    v_game_id uuid;
    v_test_id uuid;
BEGIN
    -- 获取当前玩家 ID
    SELECT id INTO v_player_id FROM public.players WHERE auth_uid = auth.uid() LIMIT 1;
    
    -- 获取目标玩家 ID
    SELECT id INTO v_target_id FROM public.players WHERE username = 'fengjie' LIMIT 1;
    
    -- 使用默认游戏 ID
    v_game_id := '00000000-0000-0000-0000-000000000001'::uuid;
    
    -- 生成新流言 ID
    v_test_id := gen_random_uuid();
    
    RAISE NOTICE '当前玩家 ID: %', v_player_id;
    RAISE NOTICE '目标玩家 ID: %', v_target_id;
    RAISE NOTICE '游戏 ID: %', v_game_id;
    
    -- 测试插入
    BEGIN
        INSERT INTO public.rumors (id, game_id, publisher_uid, target_uid, content, source_type, stage)
        VALUES (v_test_id, v_game_id, v_player_id, COALESCE(v_target_id, v_player_id), 'RLS 测试流言', 'freewrite', 1);
        RAISE NOTICE '插入成功！';
    EXCEPTION WHEN OTHERS THEN
        RAISE NOTICE '插入失败：% %', SQLERRM, SQLSTATE;
    END;
END $$;

-- 6. 检查 RLS 策略评估
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    roles,
    qual,
    with_check,
    pg_get_expr(qual::oid, 0) AS qual_expression,
    pg_get_expr(with_check::oid, 0) AS check_expression
FROM pg_policies
WHERE tablename = 'rumors';

-- 7. 检查是否有其他 RLS 策略阻止插入
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    permissive,
    roles
FROM pg_policies
WHERE tablename = 'rumors'
ORDER BY tablename, policyname;

-- 8. 尝试临时禁用 RLS 测试
ALTER TABLE public.rumors DISABLE ROW LEVEL SECURITY;

-- 再次测试插入
DO $$
DECLARE
    v_player_id uuid;
    v_test_id uuid;
BEGIN
    SELECT id INTO v_player_id FROM public.players WHERE auth_uid = auth.uid() LIMIT 1;
    v_test_id := gen_random_uuid();
    
    INSERT INTO public.rumors (id, game_id, publisher_uid, target_uid, content, source_type, stage)
    VALUES (v_test_id, '00000000-0000-0000-0000-000000000001'::uuid, v_player_id, v_player_id, '禁用 RLS 测试', 'freewrite', 1);
    
    RAISE NOTICE '禁用 RLS 后插入成功！';
    
    -- 清理测试数据
    DELETE FROM public.rumors WHERE id = v_test_id;
END $$;

-- 重新启用 RLS
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;

-- 9. 检查 authenticated 角色是否存在
SELECT rolname FROM pg_roles WHERE rolname = 'authenticated';

-- 10. 检查当前会话的角色
SELECT current_user, session_user;
