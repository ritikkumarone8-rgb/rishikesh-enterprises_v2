// deno-lint-ignore-file no-explicit-any
import { createClient, SupabaseClient } from 'https://esm.sh/@supabase/supabase-js@2';

/**
 * Two clients, two very different trust levels — never mix them up:
 *
 *  - `userClient(req)`  — authenticated AS THE CALLER (their JWT is forwarded
 *    from the Authorization header). Row Level Security applies exactly as
 *    it would from the app. Use this ONLY to confirm who is calling
 *    (`auth.getUser()`) or to run RLS-scoped reads on their behalf.
 *
 *  - `serviceClient()`  — authenticated as the service role. This BYPASSES
 *    Row Level Security entirely. It is what lets this function write an
 *    `orders` row even though the `orders` table has no insert policy for
 *    ordinary users. Never return this client's raw query results directly
 *    to the caller without checking ownership yourself first — RLS is not
 *    protecting you here, your own code is.
 */
export function userClient(req: Request): SupabaseClient {
  const authHeader = req.headers.get('Authorization') ?? '';
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: authHeader } } }
  );
}

export function serviceClient(): SupabaseClient {
  return createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { persistSession: false } }
  );
}

/** Resolves the verified, logged-in customer's auth.users id, or null. */
export async function getAuthedCustomerId(req: Request): Promise<string | null> {
  const supabase = userClient(req);
  const { data, error } = await supabase.auth.getUser();
  if (error || !data?.user) return null;
  return data.user.id;
}
