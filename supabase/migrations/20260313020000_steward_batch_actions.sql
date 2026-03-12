-- Steward batch actions & stamina RPCs
-- 实现文档中 2-5 ～ 2-11 的核心服务器逻辑

-- 1) 采办物资用的“分配权”表
CREATE TABLE IF NOT EXISTS public.procurement_tickets (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES public.games(id) ON DELETE CASCADE,
    steward_uid uuid NOT NULL REFERENCES public.players(id),
    item_template_key text NOT NULL,
    quantity int NOT NULL DEFAULT 1 CHECK (quantity > 0),
    status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','used','cancelled')),
    created_at timestamptz DEFAULT now(),
    used_at timestamptz
);

ALTER TABLE public.procurement_tickets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "steward_owns_tickets" ON public.procurement_tickets
  FOR ALL
  USING (steward_uid = public.get_my_player_id())
  WITH CHECK (steward_uid = public.get_my_player_id());

GRANT ALL ON public.procurement_tickets TO authenticated;

-- 2) 情报封锁字段扩展
ALTER TABLE public.intel_fragments
  ADD COLUMN IF NOT EXISTS is_blocked boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS blocked_until timestamptz,
  ADD COLUMN IF NOT EXISTS blocked_by uuid REFERENCES public.players(id);

-- 3) 通用：管家身份校验 + 精力结算 & 扣减
CREATE OR REPLACE FUNCTION public.require_steward_and_consume_stamina(p_cost int)
RETURNS TABLE (steward_id uuid, game_id uuid, remaining_stamina int) AS $$
DECLARE
    v_player_id uuid;
    v_role text;
    v_game_id uuid;
    v_stamina int;
    v_max int;
    v_last timestamptz;
    v_now timestamptz;
    v_recovered int;
    v_interval_seconds int := 7200; -- 每2小时恢复1点
BEGIN
    -- 基于当前会话获取玩家
    SELECT id, role_class, current_game_id, stamina, stamina_max, stamina_refreshed_at
    INTO v_player_id, v_role, v_game_id, v_stamina, v_max, v_last
    FROM public.players
    WHERE id = public.get_my_player_id();

    IF v_player_id IS NULL THEN
        RAISE EXCEPTION '玩家不存在';
    END IF;

    IF v_role <> 'steward' THEN
        RAISE EXCEPTION '仅管家可用';
    END IF;

    v_now := now();
    IF v_last IS NULL THEN
        v_last := v_now;
    END IF;

    v_recovered := floor(extract(epoch FROM (v_now - v_last))::int / v_interval_seconds);
    v_stamina := LEAST(v_stamina + v_recovered, v_max);

    IF v_stamina < p_cost THEN
        RAISE EXCEPTION '精力不足';
    END IF;

    v_stamina := v_stamina - p_cost;

    UPDATE public.players
    SET stamina = v_stamina,
        stamina_refreshed_at = v_now,
        updated_at = v_now
    WHERE id = v_player_id;

    RETURN QUERY SELECT v_player_id, v_game_id, v_stamina;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.require_steward_and_consume_stamina(int) TO authenticated;

-- 4) 2-6 采办物资
CREATE OR REPLACE FUNCTION public.steward_procure_goods(
    p_item_template_key text,
    p_quantity int DEFAULT 1
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_ticket_id uuid;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_quantity IS NULL OR p_quantity <= 0 THEN
        p_quantity := 1;
    END IF;

    INSERT INTO public.procurement_tickets (game_id, steward_uid, item_template_key, quantity)
    VALUES (v_game_id, v_steward_id, p_item_template_key, p_quantity)
    RETURNING id INTO v_ticket_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_uid,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'procurement', NULL,
        1,
        jsonb_build_object(
            'item_template_key', p_item_template_key,
            'quantity', p_quantity,
            'ticket_id', v_ticket_id
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'ticket_id', v_ticket_id,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.steward_procure_goods(text, int) TO authenticated;

-- 5) 2-7 差使分派
CREATE OR REPLACE FUNCTION public.steward_assign_task(
    p_target_uid uuid,
    p_silver_reward int DEFAULT 10
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_new_silver int;
    v_new_stamina int;
    v_message_id uuid;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_target_uid IS NULL THEN
        RAISE EXCEPTION '目标玩家不能为空';
    END IF;

    -- 目标玩家精力 -2（不低于0），银两 +X
    UPDATE public.players
    SET silver = silver + COALESCE(p_silver_reward, 0),
        stamina = GREATEST(stamina - 2, 0),
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver, stamina INTO v_new_silver, v_new_stamina;

    -- 写一条“差事”消息
    INSERT INTO public.messages (
        game_id, sender_uid, receiver_uid,
        content, message_type, stamina_cost, attachments
    ) VALUES (
        v_game_id,
        v_steward_id,
        p_target_uid,
        '你被派去办理一桩差事，略感辛劳，却得了些许赏银。',
        'batch_order',
        2,
        '[]'::jsonb
    )
    RETURNING id INTO v_message_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_uid,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'assignment', p_target_uid,
        1,
        jsonb_build_object(
            'silver_reward', COALESCE(p_silver_reward, 0),
            'message_id', v_message_id
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'target_silver', v_new_silver,
        'target_stamina', v_new_stamina,
        'stamina', v_remaining,
        'message_id', v_message_id
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.steward_assign_task(uuid, int) TO authenticated;

-- 6) 2-8 预支批条
CREATE OR REPLACE FUNCTION public.steward_advance_credit(
    p_target_uid uuid,
    p_amount int DEFAULT 20,
    p_deficit_step int DEFAULT 5
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_new_silver int;
    v_new_deficit float;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_target_uid IS NULL THEN
        RAISE EXCEPTION '目标玩家不能为空';
    END IF;

    IF p_amount IS NULL OR p_amount <= 0 THEN
        RAISE EXCEPTION '预支金额必须为正数';
    END IF;

    -- 发放银两
    UPDATE public.players
    SET silver = silver + p_amount,
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver INTO v_new_silver;

    -- 亏空 +5（按文档建议，这里简单做为百分比点数）
    UPDATE public.games
    SET deficit_value = COALESCE(deficit_value, 0.0) + COALESCE(p_deficit_step, 5),
        updated_at = now()
    WHERE id = v_game_id
    RETURNING deficit_value INTO v_new_deficit;

    INSERT INTO public.deficit_log (
        game_id, operated_at, operated_by, delta_amount, new_deficit_percent
    ) VALUES (
        v_game_id, now(), v_steward_id, COALESCE(p_deficit_step, 5), v_new_deficit
    );

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_uid,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'advance', p_target_uid,
        1,
        jsonb_build_object(
            'amount', p_amount,
            'deficit_step', COALESCE(p_deficit_step, 5)
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'target_silver', v_new_silver,
        'deficit_value', v_new_deficit,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.steward_advance_credit(uuid, int, int) TO authenticated;

-- 7) 2-9 搜检功能
CREATE OR REPLACE FUNCTION public.steward_search_players(
    p_min_count int DEFAULT 5,
    p_max_count int DEFAULT 10,
    p_love_letter_rate float DEFAULT 0.3,
    p_account_fragment_rate float DEFAULT 0.25
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_n int;
    v_player record;
    v_results jsonb := '[]'::jsonb;
    v_found_love boolean;
    v_found_account boolean;
    v_any_loot boolean;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(2);

    IF p_min_count < 1 THEN p_min_count := 1; END IF;
    IF p_max_count < p_min_count THEN p_max_count := p_min_count; END IF;

    v_n := floor(random() * (p_max_count - p_min_count + 1))::int + p_min_count;

    FOR v_player IN
        SELECT id, character_name
        FROM public.players
        WHERE current_game_id = v_game_id
          AND id <> v_steward_id
        ORDER BY random()
        LIMIT v_n
    LOOP
        v_found_love := (random() < p_love_letter_rate);
        v_found_account := (random() < p_account_fragment_rate);
        v_any_loot := false;

        IF v_found_love THEN
            v_any_loot := true;
            INSERT INTO public.intel_fragments (
                game_id, owner_uid, source_uid, content,
                intel_type, scene, value_level
            ) VALUES (
                v_game_id,
                v_steward_id,
                v_player.id,
                format('在搜检%1$s时，意外发现一封藏好的情书。', COALESCE(v_player.character_name, '某人')),
                'private_action',
                'bridge',
                2
            );
        END IF;

        IF v_found_account THEN
            v_any_loot := true;
            INSERT INTO public.intel_fragments (
                game_id, owner_uid, source_uid, content,
                intel_type, scene, value_level
            ) VALUES (
                v_game_id,
                v_steward_id,
                v_player.id,
                format('从%1$s的物件中翻出几张来路不明的账目碎片。', COALESCE(v_player.character_name, '某人')),
                'account_leak',
                'treasury_back',
                3
            );
        END IF;

        v_results := v_results || jsonb_build_object(
            'player_id', v_player.id,
            'player_name', v_player.character_name,
            'found_love_letter', v_found_love,
            'found_account_fragment', v_found_account,
            'has_loot', v_any_loot
        );
    END LOOP;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_uid,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'search', NULL,
        2,
        jsonb_build_object('results', v_results),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'results', v_results,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.steward_search_players(int, int, float, float) TO authenticated;

-- 8) 2-10 平息流言
CREATE OR REPLACE FUNCTION public.steward_suppress_rumor(
    p_rumor_id uuid
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_exists boolean;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(2);

    IF p_rumor_id IS NULL THEN
        RAISE EXCEPTION 'rumor_id 不能为空';
    END IF;

    SELECT true
    INTO v_exists
    FROM public.rumors
    WHERE id = p_rumor_id
      AND game_id = v_game_id
    LIMIT 1;

    IF NOT COALESCE(v_exists, false) THEN
        RAISE EXCEPTION '目标流言不存在或不在当前局';
    END IF;

    UPDATE public.rumors
    SET is_suppressed = true,
        suppressed_by = v_steward_id,
        suppressed_at = now(),
        suppress_method = 'steward_order'
    WHERE id = p_rumor_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_uid,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'suppress_rumor', NULL,
        2,
        jsonb_build_object('rumor_id', p_rumor_id),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.steward_suppress_rumor(uuid) TO authenticated;

-- 9) 2-11 封锁消息
CREATE OR REPLACE FUNCTION public.steward_block_intel(
    p_intel_id uuid
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_exists boolean;
    v_block_until timestamptz;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(3);

    IF p_intel_id IS NULL THEN
        RAISE EXCEPTION 'intel_id 不能为空';
    END IF;

    SELECT true
    INTO v_exists
    FROM public.intel_fragments
    WHERE id = p_intel_id
      AND game_id = v_game_id
    LIMIT 1;

    IF NOT COALESCE(v_exists, false) THEN
        RAISE EXCEPTION '目标情报不存在或不在当前局';
    END IF;

    v_block_until := now() + interval '12 hours';

    UPDATE public.intel_fragments
    SET is_blocked = true,
        blocked_until = v_block_until,
        blocked_by = v_steward_id
    WHERE id = p_intel_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_uid,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'block_intel', NULL,
        3,
        jsonb_build_object(
            'intel_id', p_intel_id,
            'blocked_until', v_block_until
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'blocked_until', v_block_until,
        'stamina', v_remaining
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.steward_block_intel(uuid) TO authenticated;

