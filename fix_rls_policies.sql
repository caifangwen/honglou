-- 修复 messages 和 intel_fragments 表的 RLS 策略
-- 添加缺失的 INSERT、UPDATE、DELETE 策略

-- 为 messages 表添加 INSERT、UPDATE、DELETE 策略
CREATE POLICY "messages_insert" ON public.messages FOR INSERT WITH CHECK (sender_uid = get_my_player_id());
CREATE POLICY "messages_update" ON public.messages FOR UPDATE USING (sender_uid = get_my_player_id() OR receiver_uid = get_my_player_id() OR carrier_uid = get_my_player_id());
CREATE POLICY "messages_delete" ON public.messages FOR DELETE USING (sender_uid = get_my_player_id());

-- 为 intel_fragments 表添加 INSERT、UPDATE、DELETE 策略
CREATE POLICY "intel_insert" ON public.intel_fragments FOR INSERT WITH CHECK (owner_uid = get_my_player_id());
CREATE POLICY "intel_update" ON public.intel_fragments FOR UPDATE USING (owner_uid = get_my_player_id());
CREATE POLICY "intel_delete" ON public.intel_fragments FOR DELETE USING (owner_uid = get_my_player_id());
