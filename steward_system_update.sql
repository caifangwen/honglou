-- Steward System Update SQL
-- Based on the requirements for the "Grand View Garden" game

-- 1. Enum Types
DO $$ 
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'steward_route') THEN
        CREATE TYPE steward_route AS ENUM ('virtuous', 'schemer', 'undecided');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'action_type') THEN
        CREATE TYPE action_type AS ENUM ('procurement', 'assignment', 'search', 'advance', 'suppress_rumor', 'block_intel');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'approval_status') THEN
        CREATE TYPE approval_status AS ENUM ('pending', 'executed', 'cancelled');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_status') THEN
        CREATE TYPE audit_status AS ENUM ('filed', 'investigating', 'concluded');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'audit_verdict') THEN
        CREATE TYPE audit_verdict AS ENUM ('acquitted', 'demoted', 'catastrophe');
    END IF;
END $$;

-- 2. Treasury
-- Ensure game_id is unique in treasury so it can be referenced
DO $$ 
BEGIN
    -- If table exists, add unique constraint to game_id
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'treasury') THEN
        IF NOT EXISTS (SELECT 1 FROM pg_constraint WHERE conname = 'treasury_game_id_key') THEN
            ALTER TABLE treasury ADD CONSTRAINT treasury_game_id_key UNIQUE (game_id);
        END IF;
        
        -- Add missing columns if they don't exist
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'treasury' AND column_name = 'total_silver') THEN
            ALTER TABLE treasury ADD COLUMN total_silver integer DEFAULT 10000;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'treasury' AND column_name = 'daily_budget') THEN
            ALTER TABLE treasury ADD COLUMN daily_budget integer DEFAULT 1000;
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'treasury' AND column_name = 'prosperity_level') THEN
            ALTER TABLE treasury ADD COLUMN prosperity_level integer DEFAULT 1 CHECK (prosperity_level BETWEEN 1 AND 10);
        END IF;
        IF NOT EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name = 'treasury' AND column_name = 'deficit_rate') THEN
            ALTER TABLE treasury ADD COLUMN deficit_rate float DEFAULT 0.0 CHECK (deficit_rate BETWEEN 0.0 AND 1.0);
        END IF;
    ELSE
        -- Create table if not exists (with game_id as PK)
        CREATE TABLE treasury (
            game_id uuid PRIMARY KEY,
            total_silver integer DEFAULT 10000,
            daily_budget integer DEFAULT 1000,
            prosperity_level integer DEFAULT 1 CHECK (prosperity_level BETWEEN 1 AND 10),
            deficit_rate float DEFAULT 0.0 CHECK (deficit_rate BETWEEN 0.0 AND 1.0),
            updated_at timestamptz DEFAULT now()
        );
    END IF;
END $$;

-- 3. Steward Accounts
CREATE TABLE IF NOT EXISTS steward_accounts (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    steward_uid uuid NOT NULL,
    public_ledger jsonb DEFAULT '[]',
    private_ledger jsonb DEFAULT '[]',
    private_assets integer DEFAULT 0,
    prestige integer DEFAULT 50 CHECK (prestige BETWEEN 0 AND 100),
    action_route steward_route DEFAULT 'undecided',
    created_at timestamptz DEFAULT now(),
    UNIQUE(game_id, steward_uid)
);

-- 4. Allowance Records
CREATE TABLE IF NOT EXISTS allowance_records (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    steward_uid uuid NOT NULL,
    recipient_uid uuid NOT NULL,
    standard_amount integer NOT NULL,
    actual_amount integer NOT NULL,
    withheld_amount integer DEFAULT 0,
    is_public boolean DEFAULT true,
    created_at timestamptz DEFAULT now()
);

-- 5. Action Approvals
CREATE TABLE IF NOT EXISTS action_approvals (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    steward_uid uuid NOT NULL,
    action_type action_type NOT NULL,
    target_uid uuid,
    stamina_cost integer NOT NULL,
    params jsonb DEFAULT '{}',
    status approval_status DEFAULT 'pending',
    executed_at timestamptz,
    created_at timestamptz DEFAULT now()
);

-- 6. Audit Cases
CREATE TABLE IF NOT EXISTS audit_cases (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    plaintiff_uid uuid NOT NULL,
    defendant_uid uuid NOT NULL,
    evidence_fragments jsonb[] DEFAULT '{}',
    status audit_status DEFAULT 'filed',
    verdict audit_verdict,
    deadline timestamptz NOT NULL,
    elder_notes text,
    created_at timestamptz DEFAULT now()
);

-- 7. Steward Stamina
CREATE TABLE IF NOT EXISTS steward_stamina (
    uid uuid PRIMARY KEY,
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    current_stamina integer DEFAULT 6,
    max_stamina integer DEFAULT 6,
    last_refresh_at timestamptz DEFAULT now()
);

-- 8. RLS Policies
-- Note: Simplified for demonstration, actual implementation should use auth.uid()
ALTER TABLE treasury ENABLE ROW LEVEL SECURITY;
ALTER TABLE steward_accounts ENABLE ROW LEVEL SECURITY;
ALTER TABLE allowance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE action_approvals ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_cases ENABLE ROW LEVEL SECURITY;
ALTER TABLE steward_stamina ENABLE ROW LEVEL SECURITY;

-- Treasury: Anyone in the game can read, only Edge Functions (service_role) or system should update
CREATE POLICY "Game members can view treasury" ON treasury FOR SELECT USING (true);

-- Steward Accounts: Stewards can see their own private ledger, everyone sees public
CREATE POLICY "Stewards can view own account" ON steward_accounts FOR ALL USING (auth.uid() = steward_uid);
CREATE POLICY "Public can view public_ledger" ON steward_accounts FOR SELECT USING (true);

-- Allowance Records: Recipients and Stewards can view
CREATE POLICY "Involved players can view records" ON allowance_records FOR SELECT USING (auth.uid() = recipient_uid OR auth.uid() = steward_uid);

-- Action Approvals: Stewards can manage their own
CREATE POLICY "Stewards manage own actions" ON action_approvals FOR ALL USING (auth.uid() = steward_uid);

-- Audit Cases: Involved parties and Elders can view
CREATE POLICY "Audit participants can view" ON audit_cases FOR SELECT USING (auth.uid() = plaintiff_uid OR auth.uid() = defendant_uid);

-- Steward Stamina: Own stamina
CREATE POLICY "Own stamina view" ON steward_stamina FOR SELECT USING (auth.uid() = uid);

-- 10. Inventory Table
CREATE TABLE IF NOT EXISTS player_inventory (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    player_id uuid NOT NULL,
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    item_data jsonb NOT NULL,
    created_at timestamptz DEFAULT now()
);

-- 12. Votes Table for Major Decisions
CREATE TABLE IF NOT EXISTS votes (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    game_id uuid NOT NULL REFERENCES treasury(game_id),
    steward_uid uuid NOT NULL,
    player_uid uuid NOT NULL,
    action_id uuid NOT NULL,
    vote_type text NOT NULL CHECK (vote_type IN ('fair', 'unfair')),
    created_at timestamptz DEFAULT now(),
    UNIQUE(player_uid, action_id)
);

-- 13. Update RLS for Steward Accounts (More specific)
-- Only stewards can see their own private ledger
DROP POLICY IF EXISTS "Stewards can view own account" ON steward_accounts;
CREATE POLICY "Stewards can view own private ledger" ON steward_accounts 
    FOR SELECT USING (auth.uid() = steward_uid);

-- Anyone can see public_ledger
DROP POLICY IF EXISTS "Public can view public_ledger" ON steward_accounts;
CREATE POLICY "Public can view public ledger" ON steward_accounts 
    FOR SELECT USING (true);

-- 14. Add audit case counters
ALTER TABLE audit_cases ADD COLUMN IF NOT EXISTS pending_evidence_removal uuid;
ALTER TABLE audit_cases ADD COLUMN IF NOT EXISTS plaintiff_credibility integer DEFAULT 100;
ALTER TABLE audit_cases ADD COLUMN IF NOT EXISTS counter_accused boolean DEFAULT false;
ALTER TABLE audit_cases ADD COLUMN IF NOT EXISTS new_target uuid;

-- 15. Add asset transfer field
ALTER TABLE steward_accounts ADD COLUMN IF NOT EXISTS assets_transferred boolean DEFAULT false;

-- 15. RPC Functions for Edge Functions
-- Decrement treasury silver
CREATE OR REPLACE FUNCTION decrement_treasury(g_id uuid, amount integer)
RETURNS void AS $$
BEGIN
    UPDATE treasury 
    SET total_silver = total_silver - amount,
        updated_at = now()
    WHERE game_id = g_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Modify player stats (stamina and silver)
CREATE OR REPLACE FUNCTION modify_player_stats(p_id uuid, stamina_delta integer, silver_delta integer)
RETURNS void AS $$
BEGIN
    UPDATE players 
    SET stamina = GREATEST(0, LEAST(stamina_max, stamina + stamina_delta)),
        silver = silver + silver_delta,
        updated_at = now()
    WHERE id = p_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Increment deficit rate
CREATE OR REPLACE FUNCTION increment_deficit(g_id uuid, delta float)
RETURNS void AS $$
BEGIN
    UPDATE treasury 
    SET deficit_rate = LEAST(1.0, deficit_rate + delta),
        updated_at = now()
    WHERE game_id = g_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Modify relationship favor
CREATE OR REPLACE FUNCTION modify_relationship(p_a uuid, p_b uuid, favor_delta integer)
RETURNS void AS $$
BEGIN
    INSERT INTO events (game_id, event_type, payload)
    SELECT game_id, 'favor_change', jsonb_build_object('actor', p_a, 'target', p_b, 'delta', favor_delta)
    FROM players WHERE id = p_a;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

