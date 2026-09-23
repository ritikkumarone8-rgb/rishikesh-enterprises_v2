// create-razorpay-order
//
// Called AFTER the app has already created the order row via the
// `create_order` SQL RPC (payment_method = 'online'). This function's only
// job is the one thing Postgres can't do on its own: make an authenticated
// HTTPS call to Razorpay using a secret key that must never reach the app.
//
// It does NOT compute or trust any price from the client — it reads
// `grand_total` back off the order row it already validated belongs to the
// caller, and that row was itself computed server-side by create_order().
import { handleOptions, json } from '../_shared/cors.ts';
import { userClient, serviceClient, getAuthedCustomerId } from '../_shared/supabaseClients.ts';

Deno.serve(async (req: Request) => {
  const preflight = handleOptions(req);
  if (preflight) return preflight;
  if (req.method !== 'POST') return json({ error: 'METHOD_NOT_ALLOWED' }, 405);

  try {
    const customerId = await getAuthedCustomerId(req);
    if (!customerId) return json({ error: 'AUTH_REQUIRED' }, 401);

    const { order_id } = await req.json().catch(() => ({}));
    if (!order_id) return json({ error: 'MISSING_ORDER_ID' }, 400);

    // RLS-scoped read: this SELECT can only ever return the row if it
    // belongs to the caller (orders_owner_select policy). If someone
    // passes another customer's order_id, this simply returns nothing.
    const supabaseUser = userClient(req);
    const { data: order, error: orderErr } = await supabaseUser
      .from('orders')
      .select('id, order_code, grand_total, payment_method, payment_status, rzp_order_id')
      .eq('id', order_id)
      .single();

    if (orderErr || !order) return json({ error: 'ORDER_NOT_FOUND' }, 404);
    if (order.payment_method !== 'online') return json({ error: 'NOT_AN_ONLINE_ORDER' }, 400);
    if (order.payment_status === 'paid') return json({ error: 'ALREADY_PAID' }, 400);
    if (order.rzp_order_id) {
      // idempotent: a Razorpay order was already created for this order, reuse it
      return json({
        order_code: order.order_code,
        rzp_order_id: order.rzp_order_id,
        amount: Math.round(Number(order.grand_total) * 100),
        currency: 'INR',
        key_id: Deno.env.get('RAZORPAY_KEY_ID'),
      });
    }

    const amountPaise = Math.round(Number(order.grand_total) * 100);
    const keyId = Deno.env.get('RAZORPAY_KEY_ID')!;
    const keySecret = Deno.env.get('RAZORPAY_KEY_SECRET')!;

    const rzpRes = await fetch('https://api.razorpay.com/v1/orders', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: 'Basic ' + btoa(`${keyId}:${keySecret}`),
      },
      body: JSON.stringify({
        amount: amountPaise,
        currency: 'INR',
        receipt: order.order_code,
        notes: { order_id: order.id, order_code: order.order_code },
      }),
    });
    const rzpOrder = await rzpRes.json();
    if (!rzpRes.ok || !rzpOrder.id) {
      console.error('Razorpay order create failed:', rzpOrder);
      return json({ error: 'RAZORPAY_ERROR', detail: rzpOrder.error?.description }, 502);
    }

    // Attach the Razorpay order id to our order row. Customers have no
    // update policy on `orders` (only sellers do), so this write needs the
    // service-role client — which is safe here because we've already
    // proven, via the RLS-scoped read above, that this order belongs to
    // the caller.
    const supabaseService = serviceClient();
    const { error: updateErr } = await supabaseService
      .from('orders')
      .update({ rzp_order_id: rzpOrder.id })
      .eq('id', order.id);
    if (updateErr) {
      console.error('Failed to save rzp_order_id:', updateErr);
      return json({ error: 'INTERNAL_ERROR' }, 500);
    }

    return json({
      order_code: order.order_code,
      rzp_order_id: rzpOrder.id,
      amount: amountPaise,
      currency: 'INR',
      key_id: keyId,
    });
  } catch (e) {
    console.error('create-razorpay-order exception:', e);
    return json({ error: 'INTERNAL_ERROR' }, 500);
  }
});
