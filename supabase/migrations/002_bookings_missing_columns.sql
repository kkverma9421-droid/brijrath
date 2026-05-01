-- ════════════════════════════════════════════════════════════════════════════
-- BrijRath  ──  Bookings Missing Columns Fix  (v2)
-- Run in: Supabase Dashboard → SQL Editor → New query → Run
-- Safe to re-run: every statement uses ADD COLUMN IF NOT EXISTS.
-- Run AFTER 001_fleet_schema.sql.
-- ════════════════════════════════════════════════════════════════════════════


-- ─────────────────────────────────────────────────────────────────────────────
-- 1.  CUSTOMER IDENTITY
--     customer_name / customer_phone are referenced by database triggers or
--     policies set up outside this codebase.  Adding them here silences the
--     "column customer_name does not exist" error on every SELECT.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS customer_name  text,
  ADD COLUMN IF NOT EXISTS customer_phone text;


-- ─────────────────────────────────────────────────────────────────────────────
-- 2.  BOOKING META
--     cab_type    → saved by BookingService.saveBooking()
--     pickup_lat/lng → saved by saveBooking() for driver distance filtering
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS cab_type   text,
  ADD COLUMN IF NOT EXISTS pickup_lat float8,
  ADD COLUMN IF NOT EXISTS pickup_lng float8;


-- ─────────────────────────────────────────────────────────────────────────────
-- 3.  PAYMENT
--     All three columns are inserted by saveBooking() and updated by
--     completeRideWithPayment().
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS payment_method text          NOT NULL DEFAULT 'cash',
  ADD COLUMN IF NOT EXISTS payment_status text          NOT NULL DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS paid_amount    numeric(10,2) NOT NULL DEFAULT 0;


-- ─────────────────────────────────────────────────────────────────────────────
-- 4.  LEGACY DRIVER FIELDS
--     driver_id   → written by assignDriverToBooking() (legacy path)
--     driver_name → written by acceptRide() and assignRide()
--     vehicle     → written by acceptRide() and assignRide()
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS driver_id   uuid,
  ADD COLUMN IF NOT EXISTS driver_name text,
  ADD COLUMN IF NOT EXISTS vehicle     text;


-- ─────────────────────────────────────────────────────────────────────────────
-- 5.  DRIVER GPS TRACKING
--     Written by BookingService.updateDriverLocation() during an active ride.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS driver_lat float8,
  ADD COLUMN IF NOT EXISTS driver_lng float8;


-- ─────────────────────────────────────────────────────────────────────────────
-- 6.  FLEET / COMMISSION COLUMNS  (safety net — also added by 001_fleet_schema)
--     Added here WITHOUT FK constraints so this migration is safe to run even
--     if 001 has not been run yet.  FK enforcement is handled by 001.
-- ─────────────────────────────────────────────────────────────────────────────

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS assigned_driver_id  uuid,
  ADD COLUMN IF NOT EXISTS assigned_admin_id   uuid,
  ADD COLUMN IF NOT EXISTS assignment_mode     text          NOT NULL DEFAULT 'manual',
  ADD COLUMN IF NOT EXISTS platform_commission numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS admin_commission    numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS driver_earning      numeric(10,2) NOT NULL DEFAULT 0;


-- ─────────────────────────────────────────────────────────────────────────────
-- 7.  INDEXES  (skip silently if they already exist)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX IF NOT EXISTS idx_bookings_status
  ON public.bookings (status);

CREATE INDEX IF NOT EXISTS idx_bookings_driver_name
  ON public.bookings (driver_name);

CREATE INDEX IF NOT EXISTS idx_bookings_assigned_driver
  ON public.bookings (assigned_driver_id);

CREATE INDEX IF NOT EXISTS idx_bookings_assigned_admin
  ON public.bookings (assigned_admin_id);

CREATE INDEX IF NOT EXISTS idx_bookings_payment_status
  ON public.bookings (payment_status);


-- ─────────────────────────────────────────────────────────────────────────────
-- 8.  VERIFY — run this block after migration and check the output
--     You should see all columns listed below in the result.
-- ─────────────────────────────────────────────────────────────────────────────

SELECT
  column_name,
  data_type,
  column_default,
  is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name   = 'bookings'
ORDER BY ordinal_position;
