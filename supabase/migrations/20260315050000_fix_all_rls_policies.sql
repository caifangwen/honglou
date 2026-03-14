-- Fix all RLS policies for game tables
-- Execute this in Supabase SQL Editor

-- 1. Games table policies
CREATE POLICY "authenticated_select_games" ON public.games
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "authenticated_insert_games" ON public.games
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "authenticated_update_games" ON public.games
    FOR UPDATE
    TO authenticated
    USING (true);

-- 2. Players table policies
CREATE POLICY "authenticated_select_players" ON public.players
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "authenticated_insert_players" ON public.players
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "authenticated_update_players" ON public.players
    FOR UPDATE
    TO authenticated
    USING (auth.uid() = auth_uid);

-- 3. Rumors table policies (complete fix)
DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;

CREATE POLICY "authenticated_select_rumors" ON public.rumors
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "authenticated_insert_rumors" ON public.rumors
    FOR INSERT
    TO authenticated
    WITH CHECK (
        publisher_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
        AND game_id IS NOT NULL
    );

CREATE POLICY "authenticated_update_rumors" ON public.rumors
    FOR UPDATE
    TO authenticated
    USING (
        publisher_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
        OR target_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
    );

-- 4. Rumor events table policies
CREATE POLICY "authenticated_select_rumor_events" ON public.rumor_events
    FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "authenticated_insert_rumor_events" ON public.rumor_events
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

-- 5. Intel fragments table policies (complete fix)
DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;

CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments
    FOR SELECT
    TO authenticated
    USING (owner_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid()));

CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments
    FOR INSERT
    TO authenticated
    WITH CHECK (owner_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid()));

CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments
    FOR UPDATE
    TO authenticated
    USING (owner_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid()));

-- 6. Messages table policies
CREATE POLICY "authenticated_select_messages" ON public.messages
    FOR SELECT
    TO authenticated
    USING (
        sender_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
        OR receiver_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
        OR carrier_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
    );

CREATE POLICY "authenticated_insert_messages" ON public.messages
    FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "authenticated_update_messages" ON public.messages
    FOR UPDATE
    TO authenticated
    USING (
        sender_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
        OR receiver_uid = (SELECT id FROM public.players WHERE auth_uid = auth.uid())
    );
