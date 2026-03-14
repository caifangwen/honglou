-- 完整修复 RLS 权限 - 2026-03-15 最终版本
-- 在 Supabase SQL Editor 执行此脚本

-- 先删除所有旧策略
DROP POLICY IF EXISTS "authenticated_select_games" ON public.games;
DROP POLICY IF EXISTS "authenticated_insert_games" ON public.games;
DROP POLICY IF EXISTS "authenticated_update_games" ON public.games;

DROP POLICY IF EXISTS "authenticated_select_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_insert_players" ON public.players;
DROP POLICY IF EXISTS "authenticated_update_players" ON public.players;

DROP POLICY IF EXISTS "authenticated_select_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_insert_rumors" ON public.rumors;
DROP POLICY IF EXISTS "authenticated_update_rumors" ON public.rumors;

DROP POLICY IF EXISTS "authenticated_select_rumor_events" ON public.rumor_events;
DROP POLICY IF EXISTS "authenticated_insert_rumor_events" ON public.rumor_events;

DROP POLICY IF EXISTS "authenticated_select_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_insert_intel_fragments" ON public.intel_fragments;
DROP POLICY IF EXISTS "authenticated_update_intel_fragments" ON public.intel_fragments;

DROP POLICY IF EXISTS "authenticated_select_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_insert_messages" ON public.messages;
DROP POLICY IF EXISTS "authenticated_update_messages" ON public.messages;

DROP POLICY IF EXISTS "authenticated_select_steward_accounts" ON public.steward_accounts;
DROP POLICY IF EXISTS "authenticated_insert_steward_accounts" ON public.steward_accounts;
DROP POLICY IF EXISTS "authenticated_update_steward_accounts" ON public.steward_accounts;

DROP POLICY IF EXISTS "authenticated_select_treasury" ON public.treasury;
DROP POLICY IF EXISTS "authenticated_insert_treasury" ON public.treasury;
DROP POLICY IF EXISTS "authenticated_update_treasury" ON public.treasury;

DROP POLICY IF EXISTS "authenticated_select_allowance_records" ON public.allowance_records;
DROP POLICY IF EXISTS "authenticated_insert_allowance_records" ON public.allowance_records;

DROP POLICY IF EXISTS "authenticated_select_ledger_entries" ON public.ledger_entries;
DROP POLICY IF EXISTS "authenticated_insert_ledger_entries" ON public.ledger_entries;

DROP POLICY IF EXISTS "authenticated_select_deficit_log" ON public.deficit_log;
DROP POLICY IF EXISTS "authenticated_insert_deficit_log" ON public.deficit_log;

-- 创建简化版策略（允许所有认证用户）
CREATE POLICY "authenticated_select_games" ON public.games FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_games" ON public.games FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_games" ON public.games FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_players" ON public.players FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_players" ON public.players FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_players" ON public.players FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_rumors" ON public.rumors FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_rumors" ON public.rumors FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_rumors" ON public.rumors FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_rumor_events" ON public.rumor_events FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_rumor_events" ON public.rumor_events FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "authenticated_select_intel_fragments" ON public.intel_fragments FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_intel_fragments" ON public.intel_fragments FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_intel_fragments" ON public.intel_fragments FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_messages" ON public.messages FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_messages" ON public.messages FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_messages" ON public.messages FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_steward_accounts" ON public.steward_accounts FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_steward_accounts" ON public.steward_accounts FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_steward_accounts" ON public.steward_accounts FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_treasury" ON public.treasury FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_treasury" ON public.treasury FOR INSERT TO authenticated WITH CHECK (true);
CREATE POLICY "authenticated_update_treasury" ON public.treasury FOR UPDATE TO authenticated USING (true);

CREATE POLICY "authenticated_select_allowance_records" ON public.allowance_records FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_allowance_records" ON public.allowance_records FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "authenticated_select_ledger_entries" ON public.ledger_entries FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_ledger_entries" ON public.ledger_entries FOR INSERT TO authenticated WITH CHECK (true);

CREATE POLICY "authenticated_select_deficit_log" ON public.deficit_log FOR SELECT TO authenticated USING (true);
CREATE POLICY "authenticated_insert_deficit_log" ON public.deficit_log FOR INSERT TO authenticated WITH CHECK (true);
