-- Supabase RPC: purchase_intel_transaction
-- 处理蜂腰桥集市的情报交易事务

CREATE OR REPLACE FUNCTION purchase_intel_transaction(
    p_trade_id UUID,
    p_buyer_uid UUID,
    p_seller_uid UUID,
    p_fragment_id UUID,
    p_price_silver INT,
    p_price_qi INT
) RETURNS JSON AS $$
DECLARE
    v_buyer_silver INT;
    v_buyer_qi INT;
BEGIN
    -- 1. 验证交易状态
    IF NOT EXISTS (SELECT 1 FROM intel_trades WHERE id = p_trade_id AND status = 'pending') THEN
        RETURN json_build_object('success', false, 'error', '交易已失效');
    END IF;

    -- 2. 获取买家余额
    SELECT silver, qi_shu INTO v_buyer_silver, v_buyer_qi FROM players WHERE id = p_buyer_uid;

    -- 3. 校验余额
    IF p_price_silver > 0 AND v_buyer_silver < p_price_silver THEN
        RETURN json_build_object('success', false, 'error', '银两不足');
    END IF;
    IF p_price_qi > 0 AND v_buyer_qi < p_price_qi THEN
        RETURN json_build_object('success', false, 'error', '气数不足');
    END IF;

    -- 4. 执行扣款与加款
    -- 扣除买方
    UPDATE players 
    SET silver = silver - p_price_silver, 
        qi_shu = qi_shu - p_price_qi 
    WHERE id = p_buyer_uid;

    -- 增加卖方
    UPDATE players 
    SET silver = silver + p_price_silver, 
        qi_shu = qi_shu + p_price_qi 
    WHERE id = p_seller_uid;

    -- 5. 更新情报所有权
    UPDATE intel_fragments 
    SET owner_uid = p_buyer_uid, 
        is_sold = true 
    WHERE id = p_fragment_id;

    -- 6. 更新交易记录状态
    UPDATE intel_trades 
    SET status = 'completed', 
        buyer_uid = p_buyer_uid, 
        traded_at = NOW() 
    WHERE id = p_trade_id;

    RETURN json_build_object('success', true);
EXCEPTION WHEN OTHERS THEN
    RETURN json_build_object('success', false, 'error', SQLERRM);
END;
$$ LANGUAGE plpgsql;
