-- ============================================================
-- 《红楼回忆志》数据库迁移文件
-- 迁移名称：添加差事类型支持
-- 版本：2026-03-19
-- 描述：更新 steward_assign_task 函数以支持差事类型参数
-- ============================================================

-- 更新 steward_assign_task 函数，添加 p_task_type 参数
CREATE OR REPLACE FUNCTION public.steward_assign_task(
    p_target_uid uuid,
    p_silver_reward int DEFAULT 10,
    p_task_type text DEFAULT 'errand'
)
RETURNS json AS $$
DECLARE
    v_steward_id uuid;
    v_game_id uuid;
    v_remaining int;
    v_new_silver int;
    v_new_stamina int;
    v_message_id uuid;
    v_stamina_drain int;
    v_message_content text;
BEGIN
    SELECT steward_id, game_id, remaining_stamina
    INTO v_steward_id, v_game_id, v_remaining
    FROM public.require_steward_and_consume_stamina(1);

    IF p_target_uid IS NULL THEN
        RAISE EXCEPTION '目标玩家不能为空';
    END IF;

    -- 根据差事类型设置精力消耗和消息内容
    v_stamina_drain := 2; -- 默认
    v_message_content := '你被派去办理一桩差事，略感辛劳，却得了些许赏银。';
    
    IF p_task_type = 'errand' THEN
        v_stamina_drain := 2;
        v_message_content := '你被派去跑腿办事，来回奔波，幸得赏银鼓励。';
    ELSIF p_task_type = 'guard' THEN
        v_stamina_drain := 1;
        v_message_content := '你被派去看守门户，职责重大，需谨慎行事。';
    ELSIF p_task_type = 'purchase' THEN
        v_stamina_drain := 3;
        v_message_content := '你被派去采办物品，货比三家，颇费心力。';
    ELSIF p_task_type = 'message' THEN
        v_stamina_drain := 2;
        v_message_content := '你被派去传话递信，言辞需谨慎，不可有误。';
    ELSIF p_task_type = 'clean' THEN
        v_stamina_drain := 2;
        v_message_content := '你被派去打扫庭院，虽为琐事，亦不可懈怠。';
    ELSIF p_task_type = 'special' THEN
        v_stamina_drain := 4;
        v_message_content := '你被派去办理特殊差事，责任重大，需全力以赴。';
    END IF;

    -- 目标玩家精力扣除，银两增加
    UPDATE public.players
    SET silver = silver + COALESCE(p_silver_reward, 0),
        stamina = GREATEST(stamina - v_stamina_drain, 0),
        updated_at = now()
    WHERE id = p_target_uid
    RETURNING silver, stamina INTO v_new_silver, v_new_stamina;

    -- 写一条"差事"消息
    INSERT INTO public.messages (
        game_id, sender_uid, receiver_uid,
        content, message_type, stamina_cost, attachments
    ) VALUES (
        v_game_id,
        v_steward_id,
        p_target_uid,
        v_message_content,
        'batch_order',
        v_stamina_drain,
        jsonb_build_object('task_type', p_task_type, 'silver_reward', p_silver_reward)
    )
    RETURNING id INTO v_message_id;

    INSERT INTO public.action_approvals (
        game_id, steward_uid, action_type, target_id,
        stamina_cost, params, status, executed_at
    ) VALUES (
        v_game_id, v_steward_id, 'assignment', p_target_uid,
        1,
        jsonb_build_object(
            'silver_reward', COALESCE(p_silver_reward, 0),
            'message_id', v_message_id,
            'task_type', p_task_type,
            'stamina_drain', v_stamina_drain
        ),
        'executed',
        now()
    );

    RETURN json_build_object(
        'success', true,
        'target_silver', v_new_silver,
        'target_stamina', v_new_stamina,
        'stamina', v_remaining,
        'message_id', v_message_id,
        'task_type', p_task_type,
        'stamina_drain', v_stamina_drain
    );
EXCEPTION
    WHEN OTHERS THEN
        RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 创建批量差事分配函数
CREATE OR REPLACE FUNCTION public.bulk_assign_tasks(
    p_steward_uid uuid,
    p_game_id uuid,
    p_assignments jsonb[]
)
RETURNS json AS $$
DECLARE
    v_assignment jsonb;
    v_target_uid uuid;
    v_silver_reward int;
    v_task_type text;
    v_result jsonb;
    v_results jsonb[] := ARRAY[]::jsonb[];
    v_success_count int := 0;
    v_fail_count int := 0;
    v_message text;
BEGIN
    -- 验证管家身份
    IF NOT EXISTS (
        SELECT 1 FROM public.players 
        WHERE id = p_steward_uid AND role_class = 'steward'
    ) THEN
        RETURN json_build_object('success', false, 'error', '仅管家可执行批量差事分派');
    END IF;

    -- 遍历每个分派任务
    FOREACH v_assignment IN ARRAY p_assignments
    LOOP
        v_target_uid := (v_assignment->>'target_uid')::uuid;
        v_silver_reward := COALESCE((v_assignment->>'silver_reward')::int, 10);
        v_task_type := COALESCE(v_assignment->>'task_type', 'errand');

        IF v_target_uid IS NULL THEN
            v_fail_count := v_fail_count + 1;
            v_results := array_append(v_results, jsonb_build_object(
                'success', false,
                'error', '目标 UID 为空'
            ));
            CONTINUE;
        END IF;

        -- 调用单个分派函数（这里直接执行逻辑，不递归调用 RPC）
        BEGIN
            -- 执行分派逻辑
            PERFORM public.steward_assign_task(v_target_uid, v_silver_reward, v_task_type);
            v_success_count := v_success_count + 1;
            v_results := array_append(v_results, jsonb_build_object(
                'success', true,
                'target_uid', v_target_uid,
                'task_type', v_task_type,
                'silver_reward', v_silver_reward
            ));
        EXCEPTION WHEN OTHERS THEN
            v_fail_count := v_fail_count + 1;
            v_results := array_append(v_results, jsonb_build_object(
                'success', false,
                'target_uid', v_target_uid,
                'error', SQLERRM
            ));
        END;
    END LOOP;

    RETURN json_build_object(
        'success', true,
        'total_count', array_length(p_assignments, 1),
        'success_count', v_success_count,
        'fail_count', v_fail_count,
        'results', v_results
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
