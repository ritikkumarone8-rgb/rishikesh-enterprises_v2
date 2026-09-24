-- =====================================================================
-- RISHIKESH ENTERPRISES — Google sign-in profile enrichment
-- Run this once, after 001_schema.sql and 002_order_rpc.sql, against the
-- same Supabase project. Safe to re-run (create or replace).
--
-- Why this exists: 001_schema.sql's handle_new_auth_user() trigger already
-- fires for EVERY new row in auth.users, regardless of which provider
-- created it — so a `customers` row is already created automatically for
-- Google sign-ins with no extra work and no duplicate-record risk (same
-- `on conflict (id) do nothing`, keyed by auth.users.id, as before). This
-- migration only makes that row more useful for Google sign-ins: it also
-- copies the display name / email Google provides (in
-- auth.users.raw_user_meta_data / auth.users.email) into
-- customers.name / customers.email, which the original trigger correctly
-- left null for phone-OTP sign-ins (phone OTP never provides a name or
-- email).
--
-- Nothing here changes phone-OTP behaviour: new.phone is null for a Google
-- sign-in and new.raw_user_meta_data has no full_name/name for a phone
-- sign-in, so each column is populated only when the provider actually
-- supplied it.
-- =====================================================================

create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into customers (id, phone, name, email)
  values (
    new.id,
    new.phone,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name'),
    new.email
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

-- trg_on_auth_user_created (created in 001_schema.sql) already points at
-- handle_new_auth_user() by name, so re-creating the function above is
-- enough — no need to touch the trigger itself.
