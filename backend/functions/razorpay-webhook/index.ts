// razorpay-webhook
//
// Reliability fallback. `verify-payment` (called from the app right after
// checkout) is the normal path, but if the customer's connection drops or
// they close the app the instant after paying, that call might never
// happen — leaving a paid order stuck as "pending" forever. Razorpay also
// calls THIS endpoint directly, server-to-server, whenever a payment is
// captured, so the order still gets marked paid even if the app never
// checks back in.
//
// This is called by Razorpay's servers, not by the app — there is no user
// JWT here at all. Trust comes entirely from the webhook signature, a
// DIFFERENT secret than the API key secret (set separately in the
// Razorpay dashboard when you register this URL as a webhook).
//
// Configure in Razorpay Dashboard -> Settings -> Webhooks:
//   URL: https://<project>.supabase.co/functions/v1/razorpay-webhook
//   Active events: payment.captured, payment.failed
import { serviceClient } from '../_shared/supabaseClients.ts';

async function hmacSha256Hex(secret: string, message: string): Promise<string> {
  const enc = new TextEncoder();
  const key = await crypto.subtle.importKey(
    'raw', enc.encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']
  );
  const sig = await crypto.subtle.sign('HMAC', key, enc.encode(message));
  return [...new Uint8Array(sig)].map((b) => b.toString(16).padStart(2, '0')).join('');
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return new Response('method not allowed', { status: 405 });

  const rawBody = await req.text();
  const signature = req.headers.get('x-razorpay-signature') ?? '';
  const webhookSecret = Deno.env.get('RAZORPAY_WEBHOOK_SECRET')!;

  const expected = await hmacSha256Hex(webhookSecret, rawBody);
  if (expected !== signature) {
    console.error('razorpay-webhook: signature mismatch — rejecting');
    return new Response('invalid signature', { status: 400 });
  }

  let payload: any;
  try { payload = JSON.parse(rawBody); } catch { return new Response('bad json', { status: 400 }); }

  const event = payload.event;
  const paymentEntity = payload.payload?.payment?.entity;
  if (!paymentEntity) return new Response('ok', { status: 200 }); // nothing to do, ack anyway

  const rzpOrderId = paymentEntity.order_id;
  const rzpPaymentId = paymentEntity.id;
  const supabase = serviceClient();

  if (event === 'payment.captured') {
    const { data: order } = await supabase
      .from('orders')
      .select('id, payment_status')
      .eq('rzp_order_id', rzpOrderId)
      .single();
    if (order && order.payment_status !== 'paid') {
      await supabase
        .from('orders')
        .update({ payment_status: 'paid', status: 'confirmed', rzp_payment_id: rzpPaymentId })
        .eq('id', order.id);
    }
  } else if (event === 'payment.failed') {
    const { data: order } = await supabase
      .from('orders')
      .select('id, payment_status')
      .eq('rzp_order_id', rzpOrderId)
      .single();
    if (order && order.payment_status === 'pending') {
      await supabase.from('orders').update({ payment_status: 'failed' }).eq('id', order.id);
    }
  }

  // Always 200 so Razorpay doesn't keep retrying an event we've already handled.
  return new Response('ok', { status: 200 });
});
