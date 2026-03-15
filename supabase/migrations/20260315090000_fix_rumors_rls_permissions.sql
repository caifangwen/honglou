-- Fix rumors table RLS policies to allow authenticated users full access
-- Created: 2026-03-15

-- 1. Enable RLS on rumors table
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies for rumors table
DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;
DROP POLICY IF EXISTS "Enable insert for authenticated users only" ON public.rumors;
DROP POLICY IF EXISTS "Enable read access for all authenticated users" ON public.rumors;
DROP POLICY IF EXISTS "Enable update for authenticated users" ON public.rumors;

-- 3. Create new policies with proper permissions
-- Allow authenticated users to select rumors
CREATE POLICY "authenticated_select_rumors" ON public.rumors
FOR SELECT TO authenticated
USING (true);

-- Allow authenticated users to insert rumors
CREATE POLICY "authenticated_insert_rumors" ON public.rumors
FOR INSERT TO authenticated
WITH CHECK (true);

-- Allow authenticated users to update rumors
CREATE POLICY "authenticated_update_rumors" ON public.rumors
FOR UPDATE TO authenticated
USING (true);

-- 4. Fix intel_fragments table RLS policies
ALTER TABLE public.intel_fragments ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_insert_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;

CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
FOR SELECT TO authenticated
USING (true);

CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments
FOR INSERT TO authenticated
WITH CHECK (true);

CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
FOR UPDATE TO authenticated
USING (true);

-- 5. Verify policies are created
SELECT 
    schemaname,
    tablename,
    policyname,
    cmd,
    roles
FROM pg_policies
WHERE tablename IN ('rumors', 'intel_fragments')
ORDER BY tablename, policyname;
