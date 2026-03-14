-- Fix rumors table RLS policies for publish-rumor edge function
-- Allow authenticated users to insert and update rumors

CREATE POLICY "authenticated_insert_rumors" ON public.rumors
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "authenticated_update_rumors" ON public.rumors
    FOR UPDATE
    TO authenticated
    USING (true);

CREATE POLICY "authenticated_select_rumors" ON public.rumors
    FOR SELECT
    TO authenticated
    USING (true);

-- Fix intel_fragments RLS policies
CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
    FOR UPDATE
    TO authenticated
    USING (true);
