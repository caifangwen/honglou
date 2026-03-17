-- ============================================================
-- 修复 eavesdrop_sessions 表的 RLS 策略
-- 允许 anon 角色访问（本地开发环境）
-- 使用方法：docker exec -i honglou_local_db psql -U postgres -d honglou < fix_eavesdrop_rls.sql
-- ============================================================

-- 1. 先禁用现有的 authenticated 策略
DROP POLICY IF EXISTS "authenticated_select_eavesdrop_sessions" ON public.eavesdrop_sessions;
DROP POLICY IF EXISTS "authenticated_insert_eavesdrop_sessions" ON public.eavesdrop_sessions;
DROP POLICY IF EXISTS "authenticated_update_eavesdrop_sessions" ON public.eavesdrop_sessions;
DROP POLICY IF EXISTS "authenticated_delete_eavesdrop_sessions" ON public.eavesdrop_sessions;

-- 2. 创建允许 anon 角色的策略
CREATE POLICY "anon_select_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR SELECT TO anon USING (true);

CREATE POLICY "anon_insert_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR UPDATE TO anon USING (true);

CREATE POLICY "anon_delete_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR DELETE TO anon USING (true);

-- 3. 同时也保留 authenticated 角色的权限（云端兼容）
CREATE POLICY "authenticated_select_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated_insert_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "authenticated_update_eavesdrop_sessions" ON public.eavesdrop_sessions
    FOR UPDATE TO authenticated USING (true);

-- 4. 同样修复 intel_fragments 表
DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_insert_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_delete_intel_fragments" ON public.intel_fragments;

CREATE POLICY "anon_select_intel_fragments" ON public.intel_fragments
    FOR SELECT TO anon USING (true);

CREATE POLICY "anon_insert_intel_fragments" ON public.intel_fragments
    FOR INSERT TO anon WITH CHECK (true);

CREATE POLICY "anon_update_intel_fragments" ON public.intel_fragments
    FOR UPDATE TO anon USING (true);

CREATE POLICY "anon_delete_intel_fragments" ON public.intel_fragments
    FOR DELETE TO anon USING (true);

CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
    FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments
    FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
    FOR UPDATE TO authenticated USING (true);

-- 5. 验证策略
SELECT schemaname, tablename, policyname, permissive, roles, cmd, qual, with_check
FROM pg_policies
WHERE tablename IN ('eavesdrop_sessions', 'intel_fragments')
ORDER BY tablename, policyname;

-- 6. 测试插入（可选）
-- INSERT INTO eavesdrop_sessions (player_uid, game_id, scene, scene_key, status, ends_at)
-- VALUES (
--     '11111111-1111-1111-1111-111111111111',
--     '00000000-0000-0000-0000-000000000001',
--     'yi_hong_yuan',
--     'yi_hong_yuan',
--     'active',
--     now() + interval '1 hour'
-- );

-- SELECT count(*) FROM eavesdrop_sessions;
