-- ════════════════════════════════════════════════════════════════════════════
-- BrijRath  ──  Fleet Architecture Migration  (v1)
-- Run once in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run: every statement uses IF [NOT] EXISTS guards.
-- ════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- 1.  PROFILES  ──  extend with fleet / admin fields
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.profiles
  ADD COLUMN IF NOT EXISTS phone              text,
  ADD COLUMN IF NOT EXISTS is_active          boolean      NOT NULL DEFAULT true,
  ADD COLUMN IF NOT EXISTS commission_percent numeric(5,2) NOT NULL DEFAULT 0;

-- Widen the role domain to include the two new actor types.
-- Drop the old constraint first (it may only have customer / driver).
ALTER TABLE public.profiles
  DROP CONSTRAINT IF EXISTS profiles_role_check;

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_role_check
  CHECK (role IN ('customer', 'driver', 'admin', 'super_admin'));


-- ─────────────────────────────────────────────────────────────────────────────
-- 2.  DRIVERS  ──  fleet ownership model
--
--  profile_id  →  the Supabase auth user for this driver (nullable:
--                 admin can pre-register drivers before they sign up)
--  admin_id    →  the fleet-partner profile who owns this driver
--  priority_score  higher score = offered bookings first (super_admin knob)
--  commission_percent  % of fare the driver keeps (rest split admin/platform)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS public.drivers (
  id                 uuid         PRIMARY KEY DEFAULT gen_random_uuid(),
  profile_id         uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  admin_id           uuid         REFERENCES public.profiles(id) ON DELETE SET NULL,
  name               text         NOT NULL,
  phone              text,
  vehicle            text,
  vehicle_number     text,
  lat                float8,
  lng                float8,
  is_online          boolean      NOT NULL DEFAULT false,
  is_active          boolean      NOT NULL DEFAULT true,
  priority_score     integer      NOT NULL DEFAULT 0,
  commission_percent numeric(5,2) NOT NULL DEFAULT 80,
  created_at         timestamptz  NOT NULL DEFAULT now()
);

-- Useful indexes for fleet queries
CREATE INDEX IF NOT EXISTS idx_drivers_admin_id   ON public.drivers (admin_id);
CREATE INDEX IF NOT EXISTS idx_drivers_profile_id ON public.drivers (profile_id);
-- Partial index — only rows where the driver is currently online
CREATE INDEX IF NOT EXISTS idx_drivers_online
  ON public.drivers (admin_id, priority_score DESC)
  WHERE is_online = true AND is_active = true;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3.  BOOKINGS  ──  assignment + commission columns
--
--  assigned_driver_id  →  drivers.id  (new FK; old driver_name kept for compat)
--  assigned_admin_id   →  profiles.id of the fleet partner responsible
--  assignment_mode     →  'manual' | 'auto' | 'super_admin'
--  driver_earning      →  rupee amount the driver receives
--  admin_commission    →  rupee amount the fleet partner receives
--  platform_commission →  rupee amount BrijRath keeps
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS assigned_driver_id  uuid
    REFERENCES public.drivers(id)  ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assigned_admin_id   uuid
    REFERENCES public.profiles(id) ON DELETE SET NULL,
  ADD COLUMN IF NOT EXISTS assignment_mode     text         NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS platform_commission numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS admin_commission    numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS driver_earning      numeric(10,2) NOT NULL DEFAULT 0;

CREATE INDEX IF NOT EXISTS idx_bookings_assigned_driver
  ON public.bookings (assigned_driver_id);
CREATE INDEX IF NOT EXISTS idx_bookings_assigned_admin
  ON public.bookings (assigned_admin_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status
  ON public.bookings (status);


-- ─────────────────────────────────────────────────────────────────────────────
-- 4.  ROW LEVEL SECURITY
--
--  Bookings are left permissive for now so the existing anon customer/driver
--  flow keeps working.  Tighten each policy as auth is wired per screen.
-- ─────────────────────────────────────────────────────────────────────────────

-- ── profiles ──────────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own profile"        ON public.profiles;
DROP POLICY IF EXISTS "Super admin reads all profiles"  ON public.profiles;
DROP POLICY IF EXISTS "Admin reads driver profiles"     ON public.profiles;

-- Every authenticated user can read and write their own row.
CREATE POLICY "Users manage own profile"
  ON public.profiles FOR ALL
  USING     (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Super admin can see every profile row.
CREATE POLICY "Super admin reads all profiles"
  ON public.profiles FOR SELECT
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );

-- Admin can see the profiles of drivers they own.
CREATE POLICY "Admin reads driver profiles"
  ON public.profiles FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.drivers d
      WHERE d.profile_id = profiles.id
        AND d.admin_id   = auth.uid()
    )
  );


-- ── drivers ───────────────────────────────────────────────────────────────────
ALTER TABLE public.drivers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Admin manages own drivers"   ON public.drivers;
DROP POLICY IF EXISTS "Super admin manages drivers" ON public.drivers;
DROP POLICY IF EXISTS "Driver reads own row"        ON public.drivers;
DROP POLICY IF EXISTS "Driver updates own row"      ON public.drivers;

-- Admin can fully manage the drivers they registered.
CREATE POLICY "Admin manages own drivers"
  ON public.drivers FOR ALL
  USING     (admin_id = auth.uid())
  WITH CHECK (admin_id = auth.uid());

-- Super admin can do anything.
CREATE POLICY "Super admin manages drivers"
  ON public.drivers FOR ALL
  USING (
    (SELECT role FROM public.profiles WHERE id = auth.uid()) = 'super_admin'
  );

-- A driver can see their own row.
CREATE POLICY "Driver reads own row"
  ON public.drivers FOR SELECT
  USING (profile_id = auth.uid());

-- A driver can update their own location / online status.
CREATE POLICY "Driver updates own row"
  ON public.drivers FOR UPDATE
  USING     (profile_id = auth.uid())
  WITH CHECK (profile_id = auth.uid());


-- ── bookings  (permissive — tighten progressively) ───────────────────────────
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Anyone inserts booking"  ON public.bookings;
DROP POLICY IF EXISTS "Anyone reads bookings"   ON public.bookings;
DROP POLICY IF EXISTS "Anyone updates booking"  ON public.bookings;

CREATE POLICY "Anyone inserts booking"
  ON public.bookings FOR INSERT
  WITH CHECK (true);

CREATE POLICY "Anyone reads bookings"
  ON public.bookings FOR SELECT
  USING (true);

CREATE POLICY "Anyone updates booking"
  ON public.bookings FOR UPDATE
  USING (true);


-- ─────────────────────────────────────────────────────────────────────────────
-- 5.  HELPER VIEW  ──  admin earnings summary (optional, handy for dashboards)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_admin_earnings AS
SELECT
  b.assigned_admin_id              AS admin_id,
  p.full_name                      AS admin_name,
  COUNT(*)                         AS total_rides,
  SUM(b.paid_amount)               AS total_fare,
  SUM(b.admin_commission)          AS total_commission,
  SUM(b.driver_earning)            AS total_driver_payout,
  SUM(b.platform_commission)       AS total_platform_revenue
FROM public.bookings b
JOIN public.profiles p ON p.id = b.assigned_admin_id
WHERE b.payment_status = 'paid'
GROUP BY b.assigned_admin_id, p.full_name;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6.  HELPER VIEW  ──  driver earnings summary
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW public.v_driver_earnings AS
SELECT
  b.assigned_driver_id             AS driver_id,
  d.name                           AS driver_name,
  d.admin_id,
  COUNT(*)                         AS total_rides,
  SUM(b.paid_amount)               AS total_fare,
  SUM(b.driver_earning)            AS total_earning
FROM public.bookings b
JOIN public.drivers d ON d.id = b.assigned_driver_id
WHERE b.payment_status = 'paid'
GROUP BY b.assigned_driver_id, d.name, d.admin_id;
