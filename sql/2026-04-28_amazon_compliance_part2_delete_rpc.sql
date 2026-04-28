-- ===================================================================
-- Amazon SP-API Compliance — Part 2: delete_client_data() RPC
-- ===================================================================
-- Implements §1.7 Request for Deletion: a single transactional
-- function the Garden calls when a Client (or Amazon) asks for all
-- of a Client's data to be permanently removed.
--
-- Run AFTER part 1 (the schema migration). Idempotent: re-running
-- replaces the function with itself.
-- ===================================================================

BEGIN;

-- ─────────────────────────────────────────────────────────────────
-- 1. Permission helper: who is allowed to delete client data.
--    LOCKED to ben@joinangora.com only. This is the backend gate for the
--    Garden's Permanently-Delete-Client-Data flow. Even other super admins
--    cannot run it. Update the email below if Ben's address ever changes.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._angora_can_delete_clients()
RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT EXISTS (
    SELECT 1
      FROM auth.users u
     WHERE u.id = auth.uid()
       AND lower(u.email) = 'ben@joinangora.com'
  );
$$;

REVOKE ALL ON FUNCTION public._angora_can_delete_clients() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._angora_can_delete_clients() TO authenticated;


-- ─────────────────────────────────────────────────────────────────
-- 2. The deletion function. Returns the audit row id and a JSON
--    object of {table_name -> rows_deleted} so the Garden can show
--    a certificate.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_client_data(
  p_account_id        UUID,
  p_reason            TEXT DEFAULT NULL,
  p_amazon_notice_id  TEXT DEFAULT NULL
)
RETURNS TABLE (
  deletion_id    UUID,
  account_name   TEXT,
  initiated_at   TIMESTAMPTZ,
  completed_at   TIMESTAMPTZ,
  rows_deleted   JSONB
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id            UUID := auth.uid();
  v_user_email         TEXT;
  v_account_name       TEXT;
  v_deletion_id        UUID;
  v_initiated_at       TIMESTAMPTZ := now();
  v_completed_at       TIMESTAMPTZ;
  v_counts             JSONB := '{}'::JSONB;
  v_n                  BIGINT;
BEGIN
  -- Permission gate.
  IF NOT public._angora_can_delete_clients() THEN
    RAISE EXCEPTION 'permission denied: you need to be a super admin to delete Amazon data (ben@joinangora.com only).';
  END IF;

  -- Resolve account.
  SELECT name INTO v_account_name FROM public.angora_accounts WHERE id = p_account_id;
  IF v_account_name IS NULL THEN
    RAISE EXCEPTION 'account not found: %', p_account_id;
  END IF;

  -- Best-effort lookup of the initiating user's email.
  BEGIN
    SELECT email INTO v_user_email FROM auth.users WHERE id = v_user_id;
  EXCEPTION WHEN OTHERS THEN v_user_email := NULL;
  END;

  -- 2a. Open the audit row up front (before any deletes), so even
  --     if a delete fails we have an "initiated" record.
  INSERT INTO public.angora_data_deletions (
    account_id, account_name,
    initiated_by_user_id, initiated_by_email,
    initiated_at, reason, amazon_notice_id
  ) VALUES (
    p_account_id, v_account_name,
    v_user_id, v_user_email,
    v_initiated_at, p_reason, p_amazon_notice_id
  ) RETURNING id INTO v_deletion_id;

  -- 2b. Cascade-delete in foreign-key-safe order.

  -- Messages (child of message_threads)
  WITH d AS (
    DELETE FROM public.angora_messages
    WHERE thread_id IN (
      SELECT id FROM public.angora_message_threads WHERE account_id = p_account_id
    )
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_messages', v_n);

  -- Message threads
  WITH d AS (
    DELETE FROM public.angora_message_threads WHERE account_id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_message_threads', v_n);

  -- Inventory snapshots (child of products)
  WITH d AS (
    DELETE FROM public.angora_inventory
    WHERE product_id IN (SELECT id FROM public.angora_products WHERE account_id = p_account_id)
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_inventory', v_n);

  -- Inventory history (child of products)
  WITH d AS (
    DELETE FROM public.angora_inventory_history
    WHERE product_id IN (SELECT id FROM public.angora_products WHERE account_id = p_account_id)
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_inventory_history', v_n);

  -- Daily sales (child of products)
  WITH d AS (
    DELETE FROM public.angora_daily_sales
    WHERE product_id IN (SELECT id FROM public.angora_products WHERE account_id = p_account_id)
    RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_daily_sales', v_n);

  -- Purchase orders (child of accounts)
  WITH d AS (
    DELETE FROM public.angora_purchase_orders WHERE account_id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_purchase_orders', v_n);

  -- Notes (child of accounts)
  WITH d AS (
    DELETE FROM public.angora_notes WHERE account_id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_notes', v_n);

  -- PDF uploads (child of accounts)
  WITH d AS (
    DELETE FROM public.angora_pdf_uploads WHERE account_id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_pdf_uploads', v_n);

  -- Report uploads (child of accounts)
  WITH d AS (
    DELETE FROM public.angora_report_uploads WHERE account_id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_report_uploads', v_n);

  -- Products (child of accounts) — delete LAST among children so other
  -- product-keyed rows are gone first.
  WITH d AS (
    DELETE FROM public.angora_products WHERE account_id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_products', v_n);

  -- The account itself.
  WITH d AS (
    DELETE FROM public.angora_accounts WHERE id = p_account_id RETURNING 1
  )
  SELECT count(*) INTO v_n FROM d;
  v_counts := v_counts || jsonb_build_object('angora_accounts', v_n);

  -- 2c. Close out the audit row.
  v_completed_at := now();
  UPDATE public.angora_data_deletions
     SET completed_at = v_completed_at,
         rows_deleted = v_counts
   WHERE id = v_deletion_id;

  RETURN QUERY SELECT v_deletion_id, v_account_name, v_initiated_at, v_completed_at, v_counts;
END;
$$;

-- Grants: only authenticated users may call.
REVOKE ALL ON FUNCTION public.delete_client_data(UUID, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.delete_client_data(UUID, TEXT, TEXT) TO authenticated;

COMMENT ON FUNCTION public.delete_client_data(UUID, TEXT, TEXT) IS
  'Permanently deletes every row tied to the given Client account in FK-safe order, logs the event to angora_data_deletions, and returns the deletion id + per-table row counts. Used by the Garden Permanently Delete Client Data button to satisfy Amazon SP-API §1.7.';


-- ─────────────────────────────────────────────────────────────────
-- 3. Tiny helper used by the pre-delete confirm modal: returns the
--    row count per table for an account, WITHOUT deleting anything.
--    Lets the Garden show "this will destroy 1,847 inventory rows,
--    312 sales rows, …" before the user confirms.
-- ─────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.preview_client_data_deletion(p_account_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_counts JSONB := '{}'::JSONB;
  v_n      BIGINT;
BEGIN
  IF NOT public._angora_can_delete_clients() THEN
    RAISE EXCEPTION 'permission denied';
  END IF;

  SELECT count(*) INTO v_n FROM public.angora_messages
    WHERE thread_id IN (SELECT id FROM public.angora_message_threads WHERE account_id = p_account_id);
  v_counts := v_counts || jsonb_build_object('angora_messages', v_n);

  SELECT count(*) INTO v_n FROM public.angora_message_threads WHERE account_id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_message_threads', v_n);

  SELECT count(*) INTO v_n FROM public.angora_inventory
    WHERE product_id IN (SELECT id FROM public.angora_products WHERE account_id = p_account_id);
  v_counts := v_counts || jsonb_build_object('angora_inventory', v_n);

  SELECT count(*) INTO v_n FROM public.angora_inventory_history
    WHERE product_id IN (SELECT id FROM public.angora_products WHERE account_id = p_account_id);
  v_counts := v_counts || jsonb_build_object('angora_inventory_history', v_n);

  SELECT count(*) INTO v_n FROM public.angora_daily_sales
    WHERE product_id IN (SELECT id FROM public.angora_products WHERE account_id = p_account_id);
  v_counts := v_counts || jsonb_build_object('angora_daily_sales', v_n);

  SELECT count(*) INTO v_n FROM public.angora_purchase_orders WHERE account_id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_purchase_orders', v_n);

  SELECT count(*) INTO v_n FROM public.angora_notes WHERE account_id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_notes', v_n);

  SELECT count(*) INTO v_n FROM public.angora_pdf_uploads WHERE account_id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_pdf_uploads', v_n);

  SELECT count(*) INTO v_n FROM public.angora_report_uploads WHERE account_id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_report_uploads', v_n);

  SELECT count(*) INTO v_n FROM public.angora_products WHERE account_id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_products', v_n);

  SELECT count(*) INTO v_n FROM public.angora_accounts WHERE id = p_account_id;
  v_counts := v_counts || jsonb_build_object('angora_accounts', v_n);

  RETURN v_counts;
END;
$$;

REVOKE ALL ON FUNCTION public.preview_client_data_deletion(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_client_data_deletion(UUID) TO authenticated;

COMMENT ON FUNCTION public.preview_client_data_deletion(UUID) IS
  'Returns per-table row counts for an account without deleting. Used by the Garden delete confirm modal to show the user what is about to be destroyed.';

COMMIT;
