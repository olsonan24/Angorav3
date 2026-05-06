ALTER TABLE public.angora_products ADD COLUMN IF NOT EXISTS fb_fees NUMERIC DEFAULT NULL;
NOTIFY pgrst, 'reload schema';
