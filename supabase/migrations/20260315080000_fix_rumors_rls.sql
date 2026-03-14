-- Fix RLS policies for rumors table
-- Run this in Supabase SQL Editor

-- 1. Enable RLS on rumors table if not already enabled
ALTER TABLE public.rumors ENABLE ROW LEVEL SECURITY;

-- 2. Drop existing policies for rumors table
DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;

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

-- 4. Verify policies are created
SELECT 
    schemaname,
    tablename,
    policyname,
    permissive,
    roles,
    cmd,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'rumors';
