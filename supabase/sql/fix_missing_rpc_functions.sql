-- ============================================================
-- 《红楼回忆志》数据库修复脚本
-- 添加缺失的月例发放 RPC 函数
-- 版本：2026-03-19
-- ============================================================

-- 月例发放 RPC 函数
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
    v_new_deficit float;
    v_withheld int;
    v_steward_private_silver int;
BEGIN
    -- 验证管家身份
    IF NOT EXISTS (
        SELECT 1 FROM public.players 
        WHERE id = p_steward_uid AND role_class = 'steward'
    ) THEN
        RETURN json_build_object('success', false, 'error', '仅管家可发放月例');
    END IF;

    -- 计算克扣金额
    v_withheld := p_standard_amount - p_actual_amount;

    -- 更新管家私产（克扣部分进入管家私账）
    UPDATE public.players
    SET private_silver = private_silver + COALESCE(v_withheld, 0),
        silver = silver + COALESCE(p_actual_amount, 0),
        updated_at = now()
    WHERE id = p_recipient_uid;

    -- 更新管家账本
    IF v_withheld > 0 THEN
        -- 有克扣，记录到暗账
        UPDATE public.steward_accounts
        SET private_ledger = private_ledger || jsonb_build_array(
            jsonb_build_object(
                'recipient_uid', p_recipient_uid,
                'recipient_name', p_recipient_name,
                'withheld', v_withheld,
                'standard', p_standard_amount,
                'actual', p_actual_amount,
                'timestamp', now()
            )
        ),
        updated_at = now()
        WHERE steward_uid = p_steward_uid AND game_id = p_game_id;
    END IF;

    -- 记录到公账
    UPDATE public.steward_accounts
    SET public_ledger = public_ledger || jsonb_build_array(
        jsonb_build_object(
            'recipient_uid', p_recipient_uid,
            'recipient_name', p_recipient_name,
            'amount', p_actual_amount,
            'standard', p_standard_amount,
            'timestamp', now()
        )
    ),
    updated_at = now()
    WHERE steward_uid = p_steward_uid AND game_id = p_game_id;

    -- 插入 allowance_records 记录
    INSERT INTO public.allowance_records (
        game_id, player_id, issued_by, 
        amount_public, amount_actual, withheld_amount
    ) VALUES (
        p_game_id, p_recipient_uid, p_steward_uid,
        p_standard_amount, p_actual_amount, v_withheld
    );

    -- 重新计算亏空百分比
    SELECT COALESCE(deficit_value, 0.0) INTO v_new_deficit
    FROM public.games WHERE id = p_game_id;

    RETURN json_build_object(
        'success', true,
        'withheld', v_withheld,
        'new_deficit', v_new_deficit
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 批量发放月例 RPC 函数
CREATE OR REPLACE FUNCTION public.bulk_distribute_allowance_rpc(
    p_steward_uid uuid,
    p_game_id uuid,
    p_distributions jsonb[]
)
RETURNS json AS $$
DECLARE
    v_dist jsonb;
    v_recipient_uid uuid;
    v_recipient_name text;
    v_actual int;
    v_standard int;
    v_total_withheld int := 0;
    v_success_count int := 0;
    v_fail_count int := 0;
BEGIN
    -- 验证管家身份
    IF NOT EXISTS (
        SELECT 1 FROM public.players 
        WHERE id = p_steward_uid AND role_class = 'steward'
    ) THEN
        RETURN json_build_object('success', false, 'error', '仅管家可发放月例');
    END IF;

    -- 遍历每个发放记录
    FOREACH v_dist IN ARRAY p_distributions
    LOOP
        v_recipient_uid := (v_dist->>'recipient_uid')::uuid;
        v_recipient_name := v_dist->>'recipient_name';
        v_actual := COALESCE((v_dist->>'actual_amount')::int, 0);
        v_standard := COALESCE((v_dist->>'standard_amount')::int, 20);

        IF v_recipient_uid IS NULL THEN
            v_fail_count := v_fail_count + 1;
            CONTINUE;
        END IF;

        -- 发放月例
        PERFORM public.distribute_allowance_rpc(
            p_steward_uid, 
            v_recipient_uid, 
            v_recipient_name, 
            v_actual, 
            v_standard, 
            p_game_id
        );

        v_total_withheld := v_total_withheld + (v_standard - v_actual);
        v_success_count := v_success_count + 1;
    END LOOP;

    -- 更新游戏亏空值
    IF v_total_withheld > 0 THEN
        UPDATE public.games
        SET deficit_value = deficit_value + (float(v_total_withheld) / 100.0),
            updated_at = now()
        WHERE id = p_game_id;
    END IF;

    RETURN json_build_object(
        'success', true,
        'total_withheld', v_total_withheld,
        'success_count', v_success_count,
        'fail_count', v_fail_count
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 获取银库统计数据
CREATE OR REPLACE FUNCTION public.get_treasury_stats(
    p_game_id uuid
)
RETURNS TABLE (
    sum_public bigint,
    sum_withheld bigint
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COALESCE(SUM(amount_public), 0)::bigint as sum_public,
        COALESCE(SUM(withheld_amount), 0)::bigint as sum_withheld
    FROM public.allowance_records
    WHERE game_id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 授权
GRANT EXECUTE ON FUNCTION public.distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_distribute_allowance_rpc TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_treasury_stats TO authenticated;
