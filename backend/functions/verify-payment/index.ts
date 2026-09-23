// verify-payment
//
// Called by the app right after Razorpay Checkout's success `handler`
// fires. Verifies the HMAC-SHA256 signature Razorpay gives us — this is
// the ONLY trustworthy proof that a payment really happened; everything
// else in the client-side handler payload can be forged by a modified
// app, so nothing here is trusted except the signature check itself.
import { handleOptions, json } from '../_shared/cors.ts';
import { userClient, serviceClient, getAuthedCustomerId } from '../_shared/supabaseClients.ts';

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  try {
    const customerId = await getAuthedCustomerId(req);
    if (!customerId) return json({ error: 'AUTH_REQUIRED' }, 401);

    const { order_id, rzp_order_id, rzp_payment_id, signature } = await req.json().catch(() => ({}));
    if (!order_id || !rzp_order_id || !rzp_payment_id || !signature) {
      return json({ error: 'MISSING_FIELDS' }, 400);
    }

    // confirm this order really belongs to the caller (RLS-scoped read)
    const supabaseUser = userClient(req);
    const { data: order, error: orderErr } = await supabaseUser
      .from('orders')
      .select('id, order_code, rzp_order_id, payment_status')
      .eq('id', order_id)
      .single();
    if (orderErr || !order) return json({ error: 'ORDER_NOT_FOUND' }, 404);
    if (order.rzp_order_id !== rzp_order_id) return json({ error: 'ORDER_MISMATCH' }, 400);
    if (order.payment_status === 'paid') return json({ ok: true, order_code: order.order_code }); // idempotent

    const secret = Deno.env.get('RAZORPAY_KEY_SECRET')!;
    const expected = await hmacSha256Hex(secret, `${rzp_order_id}|${rzp_payment_id}`);
    if (expected !== signature) {
      console.error('Signature mismatch for order', order.order_code);
      await serviceClient().from('orders').update({ payment_status: 'failed' }).eq('id', order_id);
      return json({ error: 'SIGNATURE_INVALID' }, 400);
    }

    const { error: updateErr } = await serviceClient()
      .from('orders')
      .update({ payment_status: 'paid', status: 'confirmed', rzp_payment_id })
      .eq('id', order_id);
    if (updateErr) {
      console.error('Failed to mark order paid:', updateErr);
      return json({ error: 'INTERNAL_ERROR' }, 500);
    }

    return json({ ok: true, order_code: order.order_code });
  } catch (e) {
    console.error('verify-payment exception:', e);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
