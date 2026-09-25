-- =====================================================================
-- DUMMY / DEMO CATALOGUE DATA
-- Target: a Supabase project that already has 001_schema.sql applied.
-- Run this once in the Supabase SQL editor (or `supabase db push`) to
-- populate categories, brands, products (each with 4+ photos) and a
-- couple of homepage deals — enough to explore browsing, product
-- details, cart, seller inventory and stock updates end-to-end.
--
-- Product photos use picsum.photos placeholder images (deterministic —
-- each URL always returns the same image) since this is demo data, not
-- real product photography. Replace them with real photos any time from
-- the seller dashboard's product editor (Edit -> photos).
--
-- This file is NOT auto-applied — it is not run by the app or by CI.
-- Idempotent-ish: re-running it is safe (it clears out any rows it
-- previously inserted before re-inserting, matched by product `sku`).
--
-- Reviews are intentionally NOT seeded here: a review requires a real
-- `customers` row, which only exists once someone actually signs in via
-- phone OTP (see backend/sql/001_schema.sql, `handle_new_auth_user`).
-- To see the reviews UI populated, sign in as a customer in the app,
-- place a COD test order for one of these products, mark that order
-- "fulfilled" from the seller dashboard, then write a review from the
-- product page — the whole loop is already wired up in the app.
-- =====================================================================

-- ---------- categories ----------
insert into categories (slug, name, sort_order, is_active) values
  ('wiring-cables',      'Wiring & Cables',       1, true),
  ('switches-sockets',   'Switches & Sockets',    2, true),
  ('fans',               'Fans',                  3, true),
  ('lighting',           'Lighting',              4, true),
  ('mcb-protection',     'MCBs & Protection',     5, true),
  ('water-heaters',      'Water Heaters',         6, true)
on conflict (slug) do update set name = excluded.name, sort_order = excluded.sort_order, is_active = true;

-- ---------- brands ----------
insert into brands (name, slug, description, sort_order, is_active) values
  ('Havells',  'havells',  'Authorized Havells dealer — wiring, switches, fans, lighting and appliances.', 1, true),
  ('Anchor',   'anchor',   'Anchor by Panasonic — switches, wires and electrical accessories.',            2, true),
  ('Crompton', 'crompton', 'Crompton — fans, lighting and small appliances.',                               3, true),
  ('Polycab',  'polycab',  'Polycab — wires, cables and conduit fittings.',                                 4, true)
on conflict (slug) do update set name = excluded.name, description = excluded.description, sort_order = excluded.sort_order, is_active = true;

-- ---------- products + images ----------
-- Each block: delete any previous seed row with the same SKU (so this file
-- can be re-run safely), insert the product, then insert 4+ images for it.
do $$
declare
  v_product_id uuid;
  v_category_id uuid;
  v_brand_id uuid;
begin

  -- 1. Havells ceiling fan
  delete from products where sku = 'DEMO-FAN-HAV-01';
  select id into v_category_id from categories where slug = 'fans';
  select id into v_brand_id from brands where slug = 'havells';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-FAN-HAV-01', 'Havells Stealth Air 1200mm Ceiling Fan', v_brand_id, v_category_id,
          2199, 2799, 24,
          'High-speed 1200mm ceiling fan with a rust-proof finish and a 2-year warranty. Delivers strong air '
          'flow with low power consumption — a popular pick for living rooms and bedrooms.',
          true, true, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-fan-hav-01-1/900/900', 0, 'Havells Stealth Air ceiling fan — front view'),
    (v_product_id, 'https://picsum.photos/seed/demo-fan-hav-01-2/900/900', 1, 'Havells Stealth Air ceiling fan — side view'),
    (v_product_id, 'https://picsum.photos/seed/demo-fan-hav-01-3/900/900', 2, 'Havells Stealth Air ceiling fan — installed in room'),
    (v_product_id, 'https://picsum.photos/seed/demo-fan-hav-01-4/900/900', 3, 'Havells Stealth Air ceiling fan — box packaging');

  -- 2. Crompton ceiling fan
  delete from products where sku = 'DEMO-FAN-CRO-01';
  select id into v_category_id from categories where slug = 'fans';
  select id into v_brand_id from brands where slug = 'crompton';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-FAN-CRO-01', 'Crompton Energion Hill Briz 1200mm BLDC Fan', v_brand_id, v_category_id,
          3499, 3999, 4,
          'BLDC motor ceiling fan that uses up to 50% less electricity than a regular fan, with a remote for '
          'speed control. Includes a 3-year warranty.',
          true, false, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-fan-cro-01-1/900/900', 0, 'Crompton BLDC fan — front view'),
    (v_product_id, 'https://picsum.photos/seed/demo-fan-cro-01-2/900/900', 1, 'Crompton BLDC fan — remote control'),
    (v_product_id, 'https://picsum.photos/seed/demo-fan-cro-01-3/900/900', 2, 'Crompton BLDC fan — blade close-up'),
    (v_product_id, 'https://picsum.photos/seed/demo-fan-cro-01-4/900/900', 3, 'Crompton BLDC fan — installed');

  -- 3. Havells LED bulb
  delete from products where sku = 'DEMO-LED-HAV-09W';
  select id into v_category_id from categories where slug = 'lighting';
  select id into v_brand_id from brands where slug = 'havells';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-LED-HAV-09W', 'Havells Adore 9W LED Bulb (Cool Day Light)', v_brand_id, v_category_id,
          99, 149, 150,
          'Bright, energy-saving 9W LED bulb with a standard B22 base. Instant-on, flicker-free light with a '
          '2-year replacement warranty. Sold individually.',
          true, true, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-led-hav-09w-1/900/900', 0, 'Havells 9W LED bulb — product shot'),
    (v_product_id, 'https://picsum.photos/seed/demo-led-hav-09w-2/900/900', 1, 'Havells 9W LED bulb — packaging'),
    (v_product_id, 'https://picsum.photos/seed/demo-led-hav-09w-3/900/900', 2, 'Havells 9W LED bulb — lit'),
    (v_product_id, 'https://picsum.photos/seed/demo-led-hav-09w-4/900/900', 3, 'Havells 9W LED bulb — base close-up');

  -- 4. Crompton LED panel light
  delete from products where sku = 'DEMO-PANEL-CRO-18W';
  select id into v_category_id from categories where slug = 'lighting';
  select id into v_brand_id from brands where slug = 'crompton';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-PANEL-CRO-18W', 'Crompton 18W Round LED Panel Light', v_brand_id, v_category_id,
          349, 499, 40,
          'Slim surface/recessed round LED panel for kitchens, passages and false ceilings. Uniform, glare-free '
          'light output.',
          true, false, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-panel-cro-18w-1/900/900', 0, 'Crompton LED panel — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-panel-cro-18w-2/900/900', 1, 'Crompton LED panel — mounted on ceiling'),
    (v_product_id, 'https://picsum.photos/seed/demo-panel-cro-18w-3/900/900', 2, 'Crompton LED panel — back/driver'),
    (v_product_id, 'https://picsum.photos/seed/demo-panel-cro-18w-4/900/900', 3, 'Crompton LED panel — lit example');

  -- 5. Anchor modular switch
  delete from products where sku = 'DEMO-SW-ANC-6A';
  select id into v_category_id from categories where slug = 'switches-sockets';
  select id into v_brand_id from brands where slug = 'anchor';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-SW-ANC-6A', 'Anchor Roma 6A One-Way Modular Switch', v_brand_id, v_category_id,
          45, 65, 300,
          'Anchor Roma series 6A switch with a smooth rocker action and a fire-retardant polycarbonate body. '
          'Fits any standard modular plate.',
          true, true, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-sw-anc-6a-1/900/900', 0, 'Anchor Roma switch — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-sw-anc-6a-2/900/900', 1, 'Anchor Roma switch — on a plate'),
    (v_product_id, 'https://picsum.photos/seed/demo-sw-anc-6a-3/900/900', 2, 'Anchor Roma switch — packaging'),
    (v_product_id, 'https://picsum.photos/seed/demo-sw-anc-6a-4/900/900', 3, 'Anchor Roma switch — side angle');

  -- 6. Anchor 5-pin socket
  delete from products where sku = 'DEMO-SOCK-ANC-6A16A';
  select id into v_category_id from categories where slug = 'switches-sockets';
  select id into v_brand_id from brands where slug = 'anchor';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-SOCK-ANC-6A16A', 'Anchor Roma 6A/16A 5-Pin Socket with Safety Shutter', v_brand_id, v_category_id,
          85, 110, 220,
          'Combined 6A/16A socket that accepts both small and large appliance plugs, with a child-safe shutter '
          'over live pins.',
          true, false, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-sock-anc-1/900/900', 0, 'Anchor 5-pin socket — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-sock-anc-2/900/900', 1, 'Anchor 5-pin socket — installed'),
    (v_product_id, 'https://picsum.photos/seed/demo-sock-anc-3/900/900', 2, 'Anchor 5-pin socket — pins close-up'),
    (v_product_id, 'https://picsum.photos/seed/demo-sock-anc-4/900/900', 3, 'Anchor 5-pin socket — packaging');

  -- 7. Polycab wire (out of stock, to demonstrate that state)
  delete from products where sku = 'DEMO-WIRE-POLY-1.5';
  select id into v_category_id from categories where slug = 'wiring-cables';
  select id into v_brand_id from brands where slug = 'polycab';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-WIRE-POLY-1.5', 'Polycab 1.5 sq mm FR PVC Insulated Wire (90m coil)', v_brand_id, v_category_id,
          1899, 2199, 0,
          'Flame-retardant PVC insulated copper wire, 90-metre coil. ISI-marked, suitable for domestic house '
          'wiring circuits.',
          true, false, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-wire-poly-1/900/900', 0, 'Polycab wire coil — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-wire-poly-2/900/900', 1, 'Polycab wire coil — label close-up'),
    (v_product_id, 'https://picsum.photos/seed/demo-wire-poly-3/900/900', 2, 'Polycab wire coil — cross-section'),
    (v_product_id, 'https://picsum.photos/seed/demo-wire-poly-4/900/900', 3, 'Polycab wire coil — stacked coils');

  -- 8. Havells MCB (low stock, to demonstrate that state)
  delete from products where sku = 'DEMO-MCB-HAV-32A';
  select id into v_category_id from categories where slug = 'mcb-protection';
  select id into v_brand_id from brands where slug = 'havells';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-MCB-HAV-32A', 'Havells 32A Single Pole MCB (C Curve)', v_brand_id, v_category_id,
          220, 280, 3,
          'Miniature circuit breaker for overload and short-circuit protection on a single-phase circuit. '
          'C-curve tripping characteristic, DIN-rail mount.',
          true, false, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-mcb-hav-1/900/900', 0, 'Havells MCB — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-mcb-hav-2/900/900', 1, 'Havells MCB — mounted in panel'),
    (v_product_id, 'https://picsum.photos/seed/demo-mcb-hav-3/900/900', 2, 'Havells MCB — rating label'),
    (v_product_id, 'https://picsum.photos/seed/demo-mcb-hav-4/900/900', 3, 'Havells MCB — packaging');

  -- 9. Havells water heater
  delete from products where sku = 'DEMO-GEYSER-HAV-15L';
  select id into v_category_id from categories where slug = 'water-heaters';
  select id into v_brand_id from brands where slug = 'havells';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-GEYSER-HAV-15L', 'Havells Monza EC 15L Storage Water Heater', v_brand_id, v_category_id,
          8499, 9999, 12,
          '15-litre vertical storage water heater with a glass-lined tank, rated up to 8 bar pressure, and a '
          '5-year tank warranty. Includes a safety valve.',
          true, true, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-geyser-hav-1/900/900', 0, 'Havells 15L water heater — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-geyser-hav-2/900/900', 1, 'Havells 15L water heater — installed on wall'),
    (v_product_id, 'https://picsum.photos/seed/demo-geyser-hav-3/900/900', 2, 'Havells 15L water heater — control panel'),
    (v_product_id, 'https://picsum.photos/seed/demo-geyser-hav-4/900/900', 3, 'Havells 15L water heater — side view'),
    (v_product_id, 'https://picsum.photos/seed/demo-geyser-hav-5/900/900', 4, 'Havells 15L water heater — packaging');

  -- 10. Crompton table fan
  delete from products where sku = 'DEMO-TFAN-CRO-400';
  select id into v_category_id from categories where slug = 'fans';
  select id into v_brand_id from brands where slug = 'crompton';
  insert into products (sku, name, brand_id, category_id, price, mrp, stock, description, is_active, is_popular, coupon_eligible)
  values ('DEMO-TFAN-CRO-400', 'Crompton High Flo 400mm Table Fan', v_brand_id, v_category_id,
          1499, 1799, 18,
          '16-inch table fan with 3-speed control and a wide oscillation angle for cooling a full room.',
          true, false, true)
  returning id into v_product_id;
  insert into product_images (product_id, url, sort_order, alt_text) values
    (v_product_id, 'https://picsum.photos/seed/demo-tfan-cro-1/900/900', 0, 'Crompton table fan — front'),
    (v_product_id, 'https://picsum.photos/seed/demo-tfan-cro-2/900/900', 1, 'Crompton table fan — back with speed dial'),
    (v_product_id, 'https://picsum.photos/seed/demo-tfan-cro-3/900/900', 2, 'Crompton table fan — on a table'),
    (v_product_id, 'https://picsum.photos/seed/demo-tfan-cro-4/900/900', 3, 'Crompton table fan — packaging');

end $$;

-- ---------- homepage deals ----------
delete from deals where title in ('Fan Festival — up to 20% off', 'Lighting Upgrade Sale');
insert into deals (title, description, category_id, img, start_date, end_date, is_active)
select 'Fan Festival — up to 20% off', 'Ceiling and table fans at festival prices, while stock lasts.',
       (select id from categories where slug = 'fans'),
       'https://picsum.photos/seed/demo-deal-fans/1200/500',
       current_date, current_date + interval '30 days', true;
insert into deals (title, description, category_id, img, start_date, end_date, is_active)
select 'Lighting Upgrade Sale', 'Switch to LED — bulbs and panel lights at everyday low prices.',
       (select id from categories where slug = 'lighting'),
       'https://picsum.photos/seed/demo-deal-lighting/1200/500',
       current_date, current_date + interval '30 days', true;

-- =====================================================================
-- DONE. In the app, popular products (is_popular = true) show up on the
-- home screen; every product above is also browsable via its category.
-- The out-of-stock wire and the low-stock MCB are there on purpose, to
-- exercise those states in both the storefront and the seller dashboard.
-- =====================================================================
