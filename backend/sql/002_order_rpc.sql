-- =====================================================================
-- create_order()  —  the ONLY way an order is ever created.
--
-- Why this is a SQL function instead of app code:
--  - It runs as ONE Postgres transaction: every stock check, every stock
--    decrement and the order/order_items insert either all happen or
--    none do. Two customers racing for the last unit of a product cannot
--    both succeed (the `for update` row lock + `where stock >= qty`
--    guard makes the second one fail cleanly instead of overselling).
--  - It takes `auth.uid()` from the JWT, never a customer_id parameter —
--    so nobody can pass someone else's id and place an order "as" them.
--  - It re-reads price/mrp/stock/coupon rules from the database itself.
--    The only things it trusts from the caller are PRODUCT IDS AND
--    QUANTITIES. This is what makes client-side price tampering
--    impossible (the old site's frontend built the whole price
--    breakdown itself and just POSTed it — this function throws that
--    away and recomputes everything).
-- =====================================================================
create or replace function create_order(
  items            jsonb,             -- [{ "product_id": "...", "qty": 2 }, ...]
  p_delivery_mode  text,              -- 'delivery' | 'pickup'
  p_address_id     uuid default null,
  p_coupon_code    text default null,
  p_payment_method text default 'cod' -- 'cod' | 'online'
)
returns orders
language plpgsql
security definer
set search_path = public
as $$
declare
  v_customer_id   uuid := auth.uid();
  v_item          jsonb;
  v_product       products%rowtype;
  v_qty           int;
  v_subtotal      numeric(10,2) := 0;
  v_discount      numeric(10,2) := 0;
  v_cod_fee       numeric(10,2) := 0;
  v_grand         numeric(10,2);
  v_coupon        coupons%rowtype;
  v_coupon_base   numeric(10,2) := 0;
  v_address_snap  jsonb;
  v_order         orders;
  v_line_total    numeric(10,2);
  v_line_discount numeric(10,2);
  v_eligible_sum  numeric(10,2) := 0;
  v_discount_left numeric(10,2);
  v_lines         jsonb[] := '{}';
  v_line          jsonb;
begin
  if v_customer_id is null then
    raise exception 'AUTH_REQUIRED: you must be logged in to place an order';
  end if;
  if p_delivery_mode not in ('delivery', 'pickup') then
    raise exception 'INVALID_MODE: delivery_mode must be delivery or pickup';
  end if;
  if p_payment_method not in ('cod', 'online') then
    raise exception 'INVALID_PAYMENT: payment_method must be cod or online';
  end if;
  if jsonb_array_length(items) = 0 then
    raise exception 'EMPTY_CART: no items were provided';
  end if;

  -- make sure the customer profile row exists (defensive; the auth
  -- trigger normally already created it on sign-up)
  insert into customers (id) values (v_customer_id) on conflict (id) do nothing;

  -- resolve + snapshot the delivery address (delivery mode only)
  if p_delivery_mode = 'delivery' then
    if p_address_id is null then
      raise exception 'ADDRESS_REQUIRED: choose or add a delivery address';
    end if;
    select to_jsonb(a) into v_address_snap
      from addresses a where a.id = p_address_id and a.customer_id = v_customer_id;
    if v_address_snap is null then
      raise exception 'ADDRESS_NOT_FOUND: that address does not belong to you';
    end if;
  end if;

  -- -------- pass 1: lock rows, validate stock, compute subtotal --------
  for v_item in select * from jsonb_array_elements(items) loop
    v_qty := (v_item->>'qty')::int;
    if v_qty is null or v_qty < 1 then
      raise exception 'INVALID_QTY: quantity must be at least 1';
    end if;

    select * into v_product from products
      where id = (v_item->>'product_id')::uuid and is_active
      for update;                      -- lock so a concurrent order can't oversell this row
    if not found then
      raise exception 'PRODUCT_UNAVAILABLE: one of the items in your cart is no longer available';
    end if;
    if v_product.stock < v_qty then
      raise exception 'OUT_OF_STOCK: only % left of "%"', v_product.stock, v_product.name;
    end if;

    v_line_total := v_product.price * v_qty;
    v_subtotal := v_subtotal + v_line_total;
    v_lines := v_lines || jsonb_build_object(
      'product_id', v_product.id, 'product_name', v_product.name, 'brand', v_product.brand_name,
      'category_id', v_product.category_id, 'unit_price', v_product.price, 'qty', v_qty,
      'line_total', v_line_total, 'coupon_eligible', v_product.coupon_eligible,
      'match_category', v_product.category_id
    );
  end loop;

  -- -------- coupon: re-validated server-side, never trust a client-sent discount --------
  if p_coupon_code is not null then
    select * into v_coupon from coupons
      where lower(code) = lower(p_coupon_code) and is_active
        and (starts_at is null or starts_at <= now())
        and (ends_at is null or ends_at >= now());
    if not found then
      raise exception 'COUPON_INVALID: that coupon code is not valid';
    end if;
    if v_subtotal < v_coupon.min_order_value then
      raise exception 'COUPON_MIN_ORDER: this coupon needs a minimum order of %', v_coupon.min_order_value;
    end if;
    -- eligible base = sum of lines that match scope + are coupon_eligible
    for v_line in select * from unnest(v_lines) loop
      if (v_line->>'coupon_eligible')::boolean and (
        v_coupon.scope = 'cart'
        or (v_coupon.scope = 'category' and (v_line->>'category_id')::uuid = v_coupon.category_id)
        or (v_coupon.scope = 'product' and (v_line->>'product_id')::uuid = v_coupon.product_id)
      ) then
        v_eligible_sum := v_eligible_sum + (v_line->>'line_total')::numeric;
      end if;
    end loop;
    if v_eligible_sum > 0 then
      v_discount := case when v_coupon.discount_type = 'percent'
        then round(v_eligible_sum * v_coupon.discount_value / 100, 2)
        else v_coupon.discount_value end;
      if v_coupon.max_discount is not null and v_discount > v_coupon.max_discount then
        v_discount := v_coupon.max_discount;
      end if;
      if v_discount > v_eligible_sum then v_discount := v_eligible_sum; end if;
    end if;
  end if;

  if p_payment_method = 'cod' then v_cod_fee := 50; end if;
  v_grand := v_subtotal - v_discount + v_cod_fee;

  -- -------- write the order --------
  insert into orders (
    customer_id, delivery_mode, address_id, address_snapshot,
    coupon_id, coupon_code, subtotal, discount_total, cod_fee, grand_total,
    payment_method, payment_status, status
  ) values (
    v_customer_id, p_delivery_mode, p_address_id, v_address_snap,
    v_coupon.id, v_coupon.code, v_subtotal, v_discount, v_cod_fee, v_grand,
    p_payment_method, 'pending', 'new'
  ) returning * into v_order;

  -- -------- pass 2: distribute discount across lines, insert items, decrement stock --------
  v_discount_left := v_discount;
  for v_line in select * from unnest(v_lines) loop
    if v_eligible_sum > 0 and (v_line->>'coupon_eligible')::boolean and (
      v_coupon.scope = 'cart'
      or (v_coupon.scope = 'category' and (v_line->>'category_id')::uuid = v_coupon.category_id)
      or (v_coupon.scope = 'product' and (v_line->>'product_id')::uuid = v_coupon.product_id)
    ) then
      v_line_discount := round(v_discount * (v_line->>'line_total')::numeric / v_eligible_sum, 2);
    else
      v_line_discount := 0;
    end if;

    insert into order_items (
      order_id, product_id, product_name, brand, category_id,
      unit_price, qty, line_total, discount_amount, final_amount
    ) values (
      v_order.id, (v_line->>'product_id')::uuid, v_line->>'product_name', v_line->>'brand',
      (v_line->>'category_id')::uuid, (v_line->>'unit_price')::numeric, (v_line->>'qty')::int,
      (v_line->>'line_total')::numeric, v_line_discount, (v_line->>'line_total')::numeric - v_line_discount
    );

    update products set stock = stock - (v_line->>'qty')::int where id = (v_line->>'product_id')::uuid;
  end loop;

  return v_order;
end;
$$;

-- Only real, logged-in customers may call this — never anon, never sellers
-- acting as a customer. Sellers manage orders through their own
-- select/update policies on the tables directly.
revoke all on function create_order(jsonb, text, uuid, text, text) from public;
grant execute on function create_order(jsonb, text, uuid, text, text) to authenticated;
