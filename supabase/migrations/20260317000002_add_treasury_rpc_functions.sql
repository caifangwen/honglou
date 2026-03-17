-- ============================================================
-- 添加银库操作相关的 RPC 函数
-- 日期：2026-03-17
-- ============================================================

-- ============================================================
-- 辅助函数：修改玩家属性
-- ============================================================
CREATE OR REPLACE FUNCTION public.modify_player_stats(
    p_id uuid,
    private_silver_delta int DEFAULT 0,
    silver_delta int DEFAULT 0,
    stamina_delta int DEFAULT 0,
    reputation_delta int DEFAULT 0,
    prestige_delta int DEFAULT 0,
    loyalty_delta int DEFAULT 0
)
RETURNS json AS $$
DECLARE
    v_player record;
    v_result json;
BEGIN
    -- 获取玩家当前数据
    SELECT * INTO v_player FROM public.players WHERE id = p_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Player not found');
    END IF;
    
    -- 更新玩家属性
    UPDATE public.players
    SET 
        private_silver = GREATEST(0, private_silver + COALESCE(private_silver_delta, 0)),
        silver = GREATEST(0, silver + COALESCE(silver_delta, 0)),
        stamina = GREATEST(0, LEAST(stamina_max, stamina + COALESCE(stamina_delta, 0))),
        reputation = GREATEST(0, LEAST(100, reputation + COALESCE(reputation_delta, 0))),
        prestige = GREATEST(0, LEAST(100, prestige + COALESCE(prestige_delta, 0))),
        loyalty = GREATEST(0, LEAST(100, loyalty + COALESCE(loyalty_delta, 0))),
        updated_at = now()
    WHERE id = p_id
    RETURNING * INTO v_player;
    
    v_result := json_build_object(
        'success', true,
        'player', json_build_object(
            'id', v_player.id,
            'private_silver', v_player.private_silver,
            'silver', v_player.silver,
            'stamina', v_player.stamina,
            'reputation', v_player.reputation,
            'prestige', v_player.prestige,
            'loyalty', v_player.loyalty
        )
    );
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 辅助函数：扣除银库
-- ============================================================
CREATE OR REPLACE FUNCTION public.decrement_treasury(
    g_id uuid,
    amount int
)
RETURNS json AS $$
DECLARE
    v_treasury record;
    v_result json;
BEGIN
    -- 获取银库当前数据
    SELECT * INTO v_treasury FROM public.treasury WHERE game_id = g_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Treasury not found');
    END IF;
    
    IF v_treasury.total_silver < amount THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient funds in treasury');
    END IF;
    
    -- 扣除银两
    UPDATE public.treasury
    SET 
        total_silver = total_silver - amount,
        public_balance = public_balance - amount,
        real_balance = real_balance - amount,
        last_update = now()
    WHERE game_id = g_id
    RETURNING * INTO v_treasury;
    
    v_result := json_build_object(
        'success', true,
        'treasury', json_build_object(
            'game_id', v_treasury.game_id,
            'total_silver', v_treasury.total_silver,
            'public_balance', v_treasury.public_balance,
            'real_balance', v_treasury.real_balance
        )
    );
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 核心函数：发放月例（单人）
-- ============================================================
CREATE OR REPLACE FUNCTION public.distribute_allowance_rpc(
    p_steward_uid uuid,
    p_recipient_uid uuid,
    p_recipient_name text,
    p_actual_amount int,
    p_standard_amount int,
    p_game_id uuid
)
RETURNS json AS $$
DECLARE
    v_treasury record;
    v_steward_acc record;
    v_withheld int;
    v_ratio float;
    v_timestamp timestamptz;
    v_public_entry jsonb;
    v_private_entry jsonb;
    v_count bigint;
    v_result json;
BEGIN
    -- 1. 获取银库并校验
    SELECT * INTO v_treasury FROM public.treasury WHERE game_id = p_game_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Treasury not found');
    END IF;
    
    IF v_treasury.total_silver < p_actual_amount THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient funds in treasury');
    END IF;
    
    -- 2. 计算克扣
    v_withheld := p_standard_amount - p_actual_amount;
    v_ratio := CASE WHEN p_standard_amount > 0 THEN v_withheld::float / p_standard_amount::float ELSE 0 END;
    
    v_timestamp := now();
    
    -- 3. 扣除银库
    UPDATE public.treasury
    SET 
        total_silver = total_silver - p_actual_amount,
        public_balance = public_balance - p_actual_amount,
        real_balance = real_balance - p_actual_amount,
        last_update = v_timestamp
    WHERE game_id = p_game_id;
    
    -- 4. 更新目标玩家私产
    UPDATE public.players
    SET 
        private_silver = private_silver + p_actual_amount,
        updated_at = v_timestamp
    WHERE id = p_recipient_uid;
    
    -- 5. 获取管家账户数据
    SELECT * INTO v_steward_acc 
    FROM public.steward_accounts 
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    IF NOT FOUND THEN
        -- 初始化管家账户
        INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, private_ledger, private_assets)
        VALUES (p_game_id, p_steward_uid, '[]'::jsonb, '[]'::jsonb, 0)
        RETURNING * INTO v_steward_acc;
    END IF;
    
    -- 6. 更新明账
    v_public_entry := jsonb_build_object(
        'type', 'allowance',
        'recipient_uid', p_recipient_uid,
        'recipient_name', p_recipient_name,
        'amount', p_actual_amount,
        'timestamp', v_timestamp
    );
    
    UPDATE public.steward_accounts
    SET 
        public_ledger = COALESCE(public_ledger, '[]'::jsonb) || v_public_entry,
        updated_at = v_timestamp
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    -- 7. 更新暗账（如果有克扣）
    IF v_withheld > 0 THEN
        v_private_entry := jsonb_build_object(
            'type', 'embezzlement',
            'recipient_uid', p_recipient_uid,
            'recipient_name', p_recipient_name,
            'standard', p_standard_amount,
            'actual', p_actual_amount,
            'withheld', v_withheld,
            'timestamp', v_timestamp
        );
        
        UPDATE public.steward_accounts
        SET 
            private_ledger = COALESCE(private_ledger, '[]'::jsonb) || v_private_entry,
            private_assets = private_assets + v_withheld,
            updated_at = v_timestamp
        WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    END IF;
    
    -- 8. 写入发放记录
    INSERT INTO public.allowance_records (
        game_id, issued_by, player_id, amount_public, amount_actual, withheld_amount, issued_at
    ) VALUES (
        p_game_id, p_steward_uid, p_recipient_uid, p_standard_amount, p_actual_amount, v_withheld, v_timestamp
    );
    
    -- 9. 插入流水记录 (ledger_entries)
    INSERT INTO public.ledger_entries (
        game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
    ) VALUES (
        p_game_id, v_treasury.game_id, p_steward_uid, p_recipient_uid, 'public', 'allocation', p_actual_amount, 
        '发放月例：' || p_actual_amount || ' 两', v_timestamp
    );
    
    IF v_withheld > 0 THEN
        INSERT INTO public.ledger_entries (
            game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
        ) VALUES (
            p_game_id, v_treasury.game_id, p_steward_uid, p_recipient_uid, 'private', 'allocation', v_withheld,
            '克扣月例：' || v_withheld || ' 两', v_timestamp
        );
    END IF;
    
    -- 10. 触发告状风险检测 (本旬内克扣人数 >= 3)
    SELECT COUNT(*) INTO v_count
    FROM public.allowance_records
    WHERE issued_by = p_steward_uid
      AND game_id = p_game_id
      AND withheld_amount > 0
      AND created_at >= (now() - INTERVAL '10 days');
    
    IF v_count >= 3 THEN
        INSERT INTO public.intel_fragments (
            game_id, intel_type, content, source_uid, owner_uid, scene, scene_key
        ) VALUES (
            p_game_id, 'account_leak', 
            '有人偶然发现账房的月例支出似乎与各房领到的数额对不上。',
            p_steward_uid, p_steward_uid, 'treasury_back', 'treasury_back'
        );
    END IF;
    
    -- 11. 碎片生成逻辑 (克扣比例)
    IF v_ratio >= 0.25 OR v_ratio >= 0.10 OR v_ratio > 0 THEN
        -- 简化处理：有一定概率生成情报碎片
        IF random() < (CASE WHEN v_ratio >= 0.25 THEN 0.8 WHEN v_ratio >= 0.10 THEN 0.4 ELSE 0.15 END) THEN
            INSERT INTO public.intel_fragments (
                game_id, intel_type, content, source_uid, owner_uid, scene, scene_key
            ) VALUES (
                p_game_id, 'account_leak',
                '听闻被克扣了 ' || v_withheld || ' 两月例。',
                p_steward_uid, p_recipient_uid, 'bridge', 'bridge'
            );
        END IF;
    END IF;
    
    RETURN json_build_object('success', true, 'withheld', v_withheld);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 核心函数：批量发放月例
-- ============================================================
CREATE OR REPLACE FUNCTION public.bulk_distribute_allowance_rpc(
    p_steward_uid uuid,
    p_game_id uuid,
    p_distributions jsonb  -- Array of {recipient_uid, recipient_name, actual_amount, standard_amount}
)
RETURNS json AS $$
DECLARE
    v_treasury record;
    v_steward_acc record;
    v_dist jsonb;
    v_recipient_uid uuid;
    v_recipient_name text;
    v_actual_amount int;
    v_standard_amount int;
    v_withheld int;
    v_total_actual int := 0;
    v_total_withheld int := 0;
    v_timestamp timestamptz;
    v_public_entry jsonb;
    v_private_entry jsonb;
    v_public_ledger jsonb := '[]'::jsonb;
    v_private_ledger jsonb := '[]'::jsonb;
    v_private_assets_delta int := 0;
    v_withheld_count int := 0;
BEGIN
    -- 1. 获取银库数据
    SELECT * INTO v_treasury FROM public.treasury WHERE game_id = p_game_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object('success', false, 'error', 'Treasury not found');
    END IF;
    
    -- 2. 获取管家账户数据
    SELECT * INTO v_steward_acc 
    FROM public.steward_accounts 
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    IF NOT FOUND THEN
        INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, private_ledger, private_assets)
        VALUES (p_game_id, p_steward_uid, '[]'::jsonb, '[]'::jsonb, 0)
        RETURNING * INTO v_steward_acc;
    END IF;
    
    v_timestamp := now();
    
    -- 3. 计算总额并校验
    FOR v_dist IN SELECT * FROM jsonb_array_elements(p_distributions)
    LOOP
        v_actual_amount := (v_dist->>'actual_amount')::int;
        v_total_actual := v_total_actual + v_actual_amount;
    END LOOP;
    
    IF v_treasury.total_silver < v_total_actual THEN
        RETURN json_build_object('success', false, 'error', 'Insufficient funds in treasury');
    END IF;
    
    -- 4. 处理每一个发放
    FOR v_dist IN SELECT * FROM jsonb_array_elements(p_distributions)
    LOOP
        v_recipient_uid := (v_dist->>'recipient_uid')::uuid;
        v_recipient_name := v_dist->>'recipient_name';
        v_actual_amount := (v_dist->>'actual_amount')::int;
        v_standard_amount := (v_dist->>'standard_amount')::int;
        v_withheld := v_standard_amount - v_actual_amount;
        
        v_total_withheld := v_total_withheld + v_withheld;
        
        IF v_withheld > 0 THEN
            v_withheld_count := v_withheld_count + 1;
        END IF;
        
        -- a. 更新玩家私产
        UPDATE public.players
        SET private_silver = private_silver + v_actual_amount, updated_at = v_timestamp
        WHERE id = v_recipient_uid;
        
        -- b. 准备账本条目
        v_public_entry := jsonb_build_object(
            'type', 'allowance',
            'recipient_uid', v_recipient_uid,
            'recipient_name', v_recipient_name,
            'amount', v_actual_amount,
            'timestamp', v_timestamp
        );
        v_public_ledger := v_public_ledger || v_public_entry;
        
        IF v_withheld > 0 THEN
            v_private_entry := jsonb_build_object(
                'type', 'embezzlement',
                'recipient_uid', v_recipient_uid,
                'recipient_name', v_recipient_name,
                'standard', v_standard_amount,
                'actual', v_actual_amount,
                'withheld', v_withheld,
                'timestamp', v_timestamp
            );
            v_private_ledger := v_private_ledger || v_private_entry;
            v_private_assets_delta := v_private_assets_delta + v_withheld;
        END IF;
        
        -- c. 插入发放记录
        INSERT INTO public.allowance_records (
            game_id, issued_by, player_id, amount_public, amount_actual, withheld_amount, issued_at
        ) VALUES (
            p_game_id, p_steward_uid, v_recipient_uid, v_standard_amount, v_actual_amount, v_withheld, v_timestamp
        );
        
        -- d. 插入流水记录 (ledger_entries)
        INSERT INTO public.ledger_entries (
            game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
        ) VALUES (
            p_game_id, v_treasury.game_id, p_steward_uid, v_recipient_uid, 'public', 'allocation', v_actual_amount,
            '发放月例：' || v_actual_amount || ' 两', v_timestamp
        );
        
        IF v_withheld > 0 THEN
            INSERT INTO public.ledger_entries (
                game_id, treasury_id, actor_id, target_id, ledger_type, entry_type, amount, note, created_at
            ) VALUES (
                p_game_id, v_treasury.game_id, p_steward_uid, v_recipient_uid, 'private', 'allocation', v_withheld,
                '克扣月例：' || v_withheld || ' 两', v_timestamp
            );
        END IF;
    END LOOP;
    
    -- 5. 扣除银库
    UPDATE public.treasury
    SET 
        total_silver = total_silver - v_total_actual,
        public_balance = public_balance - v_total_actual,
        real_balance = real_balance - v_total_actual,
        last_update = v_timestamp
    WHERE game_id = p_game_id;
    
    -- 6. 更新管家账户
    UPDATE public.steward_accounts
    SET 
        public_ledger = COALESCE(public_ledger, '[]'::jsonb) || v_public_ledger,
        private_ledger = COALESCE(private_ledger, '[]'::jsonb) || v_private_ledger,
        private_assets = private_assets + v_private_assets_delta,
        updated_at = v_timestamp
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    
    -- 7. 风险检测：克扣人数 >= 3
    IF v_withheld_count >= 3 THEN
        INSERT INTO public.intel_fragments (
            game_id, intel_type, content, source_uid, owner_uid, scene, scene_key
        ) VALUES (
            p_game_id, 'account_leak',
            '本月发放月银，竟然有 ' || v_withheld_count || ' 位下人私下议论数额不对。',
            p_steward_uid, p_steward_uid, 'treasury_back', 'treasury_back'
        );
    END IF;
    
    RETURN json_build_object('success', true, 'total_distributed', v_total_actual, 'total_withheld', v_total_withheld);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ============================================================
-- 辅助函数：获取银库统计
-- ============================================================
CREATE OR REPLACE FUNCTION public.get_treasury_stats(p_game_id uuid)
RETURNS TABLE (
    sum_public bigint,
    sum_withheld bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(amount_public), 0)::bigint,
        COALESCE(SUM(withheld_amount), 0)::bigint
    FROM public.allowance_records
    WHERE game_id = p_game_id;
END;
$$ LANGUAGE plpgsql;

-- ============================================================
-- 权限授予
-- ============================================================
GRANT EXECUTE ON FUNCTION public.modify_player_stats TO authenticated;
GRANT EXECUTE ON FUNCTION public.decrement_treasury TO authenticated;
GRANT EXECUTE ON FUNCTION public.distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_treasury_stats TO authenticated;
