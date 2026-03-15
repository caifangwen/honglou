-- 修复 rumors 表的 RLS 权限问题
-- 在 Supabase SQL Editor 中运行此脚本

-- 1. 确保 RLS 已启用
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;

-- 2. 删除所有现有的 rumors 策略
DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.rumors;
DROP POLICY IF EXISTS "Enable read access for all authenticated users" ON public.rumors;
DROP POLICY IF EXISTS "Enable update for authenticated users" ON public.rumors;

-- 3. 创建新的宽松策略 - 允许所有认证用户操作
CREATE POLICY "authenticated_select_rumors" ON public.rumors
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "authenticated_insert_rumors" ON public.rumors
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "authenticated_update_rumors" ON public.rumors
FOR UPDATE TO authenticated
USING (true);

-- 4. 同样修复 intel_fragments 表
ALTER TABLE public.intel_fragments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_insert_intel_fragments" ON public.intel_fragments;

CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
FOR UPDATE TO authenticated
USING (true);

CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments
FOR INSERT TO authenticated
WITH CHECK (true);

-- 5. 验证策略已创建
SELECT 
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE tablename IN ('rumors', 'intel_fragments')
ORDER BY tablename, policyname;
