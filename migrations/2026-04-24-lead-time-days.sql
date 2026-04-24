-- 2026-04-24: Add lead_time_days column to angora_products
-- Used by the Inventory tab's Reorder Point math:
--   ROP = avg_daily * lead_time + 1.65 * (0.3*avg_daily) * sqrt(lead_time)
-- Editable per product from the Product Edit modal. Falls back to 60 if NULL.
ALTER TABLE angora_products
  ADD COLUMN IF NOT EXISTS lead_time_days INTEGER DEFAULT 60 CHECK (lead_time_days > 0 AND lead_time_days <= 365);

COMMENT ON COLUMN angora_products.lead_time_days IS 'Manufacturer lead time in days. Drives Reorder Point calc. Default 60.';
