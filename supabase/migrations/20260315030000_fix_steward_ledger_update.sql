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

    INSERT INTO public.steward_accounts (game_id, steward_uid, public_ledger, updated_at)
    VALUES (p_game_id, p_steward_uid, jsonb_build_array(v_public_entry), now())
    ON CONFLICT (game_id, steward_uid) DO UPDATE
    SET public_ledger = public.steward_accounts.public_ledger || v_public_entry,
        updated_at = now();

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
        '发放月例：' || p_actual_amount || ' 两'
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

        INSERT INTO public.steward_accounts (game_id, steward_uid, private_assets, private_ledger, updated_at)
        VALUES (p_game_id, p_steward_uid, v_withheld, jsonb_build_array(v_private_entry), now())
        ON CONFLICT (game_id, steward_uid) DO UPDATE
        SET private_assets = public.steward_accounts.private_assets + v_withheld,
            private_ledger = public.steward_accounts.private_ledger || v_private_entry,
            updated_at = now();

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
            '克扣月例：' || v_withheld || ' 两'
        );
    END IF;

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
