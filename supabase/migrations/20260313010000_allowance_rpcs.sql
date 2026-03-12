-- Allowance RPCs for Treasury UI
-- Purpose: unblock PostgREST rpc calls (distribute_allowance_rpc / bulk_distribute_allowance_rpc / get_treasury_stats)
-- Note: intel_fragments.scene uses enum scene_location; use 'treasury_back' (not 'treasury_room').

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
    v_treasury_id uuid;
    v_total_silver int;
    v_withheld int;
    v_public_entry jsonb;
    v_private_entry jsonb;
    v_withheld_count int;
BEGIN
    SELECT id, total_silver
    INTO v_treasury_id, v_total_silver
    FROM public.treasury
    WHERE game_id = p_game_id;

    IF v_treasury_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', '未找到银库数据');
    END IF;

    IF v_total_silver < p_actual_amount THEN
        RETURN json_build_object('success', false, 'error', '银库余额不足');
    END IF;

    v_withheld := p_standard_amount - p_actual_amount;

    UPDATE public.treasury
    SET total_silver = total_silver - p_actual_amount,
        updated_at = now()
    WHERE id = v_treasury_id;

    UPDATE public.players
    SET private_silver = private_silver + p_actual_amount,
        updated_at = now()
    WHERE id = p_recipient_uid;

    v_public_entry := json_build_object(
        'type', 'allowance',
        'recipient_uid', p_recipient_uid,
        'recipient_name', p_recipient_name,
        'amount', p_actual_amount,
        'timestamp', now()
    );

    UPDATE public.steward_accounts
    SET public_ledger = public_ledger || v_public_entry
    WHERE steward_uid = p_steward_uid
      AND game_id = p_game_id;

    INSERT INTO public.ledger_entries (
        game_id,
        treasury_id,
        ledger_type,
        entry_type,
        amount,
        actor_id,
        target_id,
        note
    )
    VALUES (
        p_game_id,
        v_treasury_id,
        'public',
        'allocation',
        p_actual_amount,
        p_steward_uid,
        p_recipient_uid,
        '发放月例: ' || p_actual_amount || ' 两'
    );

    IF v_withheld > 0 THEN
        v_private_entry := json_build_object(
            'type', 'embezzlement',
            'recipient_uid', p_recipient_uid,
            'recipient_name', p_recipient_name,
            'standard', p_standard_amount,
            'actual', p_actual_amount,
            'withheld', v_withheld,
            'timestamp', now()
        );

        UPDATE public.steward_accounts
        SET private_assets = private_assets + v_withheld,
            private_ledger = private_ledger || v_private_entry
        WHERE steward_uid = p_steward_uid
          AND game_id = p_game_id;

        INSERT INTO public.ledger_entries (
            game_id,
            treasury_id,
            ledger_type,
            entry_type,
            amount,
            actor_id,
            target_id,
            note
        )
        VALUES (
            p_game_id,
            v_treasury_id,
            'private',
            'allocation',
            v_withheld,
            p_steward_uid,
            p_recipient_uid,
            '克扣月例: ' || v_withheld || ' 两'
        );
    END IF;

    INSERT INTO public.allowance_records (
        game_id,
        issued_by,
        player_id,
        amount_public,
        amount_actual,
        withheld_amount
    )
    VALUES (
        p_game_id,
        p_steward_uid,
        p_recipient_uid,
        p_standard_amount,
        p_actual_amount,
        v_withheld
    );

    SELECT COUNT(*)
    INTO v_withheld_count
    FROM public.allowance_records
    WHERE game_id = p_game_id
      AND withheld_amount > 0;

    IF v_withheld_count >= 3 THEN
        INSERT INTO public.intel_fragments (
            game_id,
            intel_type,
            content,
            source_uid,
            owner_uid,
            scene
        )
        VALUES (
            p_game_id,
            'account_leak',
            '府中已有三名下人因月例被扣私下议论，管家账目恐有疏漏。',
            p_steward_uid,
            p_steward_uid,
            'treasury_back'
        );
    END IF;

    RETURN json_build_object('success', true);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.bulk_distribute_allowance_rpc(
    p_steward_uid uuid,
    p_game_id uuid,
    p_distributions jsonb
)
RETURNS json AS $$
DECLARE
    v_dist jsonb;
    v_res json;
    v_total_distributed int := 0;
BEGIN
    FOR v_dist IN
        SELECT *
        FROM jsonb_array_elements(p_distributions)
    LOOP
        v_res := public.distribute_allowance_rpc(
            p_steward_uid,
            (v_dist->>'recipient_uid')::uuid,
            v_dist->>'recipient_name',
            (v_dist->>'actual_amount')::int,
            (v_dist->>'standard_amount')::int,
            p_game_id
        );

        IF NOT (v_res->>'success')::boolean THEN
            RAISE EXCEPTION '发放失败: %', v_res->>'error';
        END IF;

        v_total_distributed := v_total_distributed + (v_dist->>'actual_amount')::int;
    END LOOP;

    RETURN json_build_object('success', true, 'total_distributed', v_total_distributed);
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE FUNCTION public.get_treasury_stats(p_game_id uuid)
RETURNS TABLE(sum_public bigint, sum_withheld bigint) AS $$
BEGIN
    RETURN QUERY
    SELECT
        COALESCE(SUM(amount_public)::bigint, 0),
        COALESCE(SUM(withheld_amount)::bigint, 0)
    FROM public.allowance_records
    WHERE game_id = p_game_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

GRANT EXECUTE ON FUNCTION public.distribute_allowance_rpc(uuid, uuid, text, int, int, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.bulk_distribute_allowance_rpc(uuid, uuid, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_treasury_stats(uuid) TO authenticated;

