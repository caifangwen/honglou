-- ## 一、核心表结构设计

-- 1. games 表：存储游戏局全局时间配置
CREATE TABLE IF NOT EXISTS public.games (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    start_timestamp bigint NOT NULL, -- Unix 时间戳 (秒)
    end_timestamp bigint,
    status text DEFAULT 'waiting' CHECK (status IN ('waiting', 'active', 'ended')),
    speed_multiplier float DEFAULT 1.0, -- 调试倍率，生产环境锁定 1.0
    deficit_value float DEFAULT 0.0, -- 亏空值 (0-100)
    conflict_value float DEFAULT 0.0, -- 内耗值 (0-100)
    created_at timestamptz DEFAULT now()
);

-- 2. game_time_events 表：时间节点触发日志
CREATE TABLE IF NOT EXISTS public.game_time_events (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    game_id uuid REFERENCES public.games(id) ON DELETE CASCADE,
    event_type text NOT NULL CHECK (event_type IN ('day_start', 'xun_end', 'month_end', 'event_trigger')),
    game_day int NOT NULL,
    game_xun int NOT NULL,
    triggered_at bigint NOT NULL,
    payload jsonb DEFAULT '{}',
    created_at timestamptz DEFAULT now()
);

-- 3. player_stamina 表：精力管理
CREATE TABLE IF NOT EXISTS public.player_stamina (
    player_id uuid PRIMARY KEY,
    game_id uuid REFERENCES public.games(id) ON DELETE CASCADE,
    current_stamina int DEFAULT 0,
    last_refresh_timestamp bigint NOT NULL, -- 上次恢复时的 Unix 时间戳
    stamina_role text DEFAULT 'maid' CHECK (stamina_role IN ('steward', 'maid')),
    max_stamina int DEFAULT 8
);

-- ## 二、核心逻辑函数

-- 1. 获取当前游戏时间的各种维度
CREATE OR REPLACE FUNCTION public.get_current_game_time(p_game_id uuid)
RETURNS json AS $$
DECLARE
    v_start bigint;
    v_speed float;
    v_now bigint;
    v_elapsed_game bigint;
    v_day int;
    v_xun int;
    v_month int;
BEGIN
    SELECT start_timestamp, speed_multiplier INTO v_start, v_speed 
    FROM public.games WHERE id = p_game_id;
    
    v_now := extract(epoch from now())::bigint;
    v_elapsed_game := (v_now - v_start) * v_speed;
    
    v_day := (v_elapsed_game / 7200) + 1;
    v_xun := (v_elapsed_game / 72000) + 1;
    v_month := (v_elapsed_game / 216000) + 1;
    
    RETURN json_build_object(
        'game_day', v_day,
        'game_xun', v_xun,
        'game_month', v_month,
        'day_progress', (v_elapsed_game % 7200) / 7200.0,
        'elapsed_game_seconds', v_elapsed_game
    );
END;
$$ LANGUAGE plpgsql;

-- 2. 计算当前精力（含自动恢复逻辑）
CREATE OR REPLACE FUNCTION public.calculate_stamina(p_player_id uuid, p_game_id uuid)
RETURNS int AS $$
DECLARE
    v_last_ts bigint;
    v_current int;
    v_max int;
    v_speed float;
    v_now bigint;
    v_recovered int;
    v_interval bigint := 7200; -- 1点精力 = 1游戏日 = 7200秒游戏时间
BEGIN
    SELECT current_stamina, last_refresh_timestamp, max_stamina INTO v_current, v_last_ts, v_max
    FROM public.player_stamina WHERE player_id = p_player_id;
    
    SELECT speed_multiplier INTO v_speed FROM public.games WHERE id = p_game_id;
    
    v_now := extract(epoch from now())::bigint;
    -- 计算经过的游戏时间秒数
    v_recovered := floor(((v_now - v_last_ts) * v_speed) / v_interval);
    
    RETURN LEAST(v_current + v_recovered, v_max);
END;
$$ LANGUAGE plpgsql;

-- 3. 旬结算触发函数
CREATE OR REPLACE FUNCTION public.trigger_xun_settlement(p_game_id uuid)
RETURNS void AS $$
BEGIN
    -- 这里可以添加业务逻辑：诗社统计、刷新清单等
    INSERT INTO public.game_time_events (game_id, event_type, game_day, game_xun, triggered_at)
    SELECT id, 'xun_end', 
           floor((extract(epoch from now()) - start_timestamp) * speed_multiplier / 7200) + 1,
           floor((extract(epoch from now()) - start_timestamp) * speed_multiplier / 72000) + 1,
           extract(epoch from now())::bigint
    FROM public.games WHERE id = p_game_id;
END;
$$ LANGUAGE plpgsql;

-- ## 三、RLS 安全策略

ALTER TABLE public.games ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.game_time_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.player_stamina ENABLE ROW LEVEL SECURITY;

-- 只有 Service Role 可以修改倍率
CREATE POLICY service_role_update_speed ON public.games
    FOR UPDATE USING (true) WITH CHECK (true);

-- 玩家只读全局时间
CREATE POLICY players_read_games ON public.games
    FOR SELECT USING (true);

-- 玩家只读事件
CREATE POLICY players_read_events ON public.game_time_events
    FOR SELECT USING (true);
