-- =====================================================================
-- RISHIKESH ENTERPRISES — new backend schema
-- Target: a fresh Supabase project (Postgres + Auth + Storage)
-- Run this whole file once in Supabase SQL editor (or `supabase db push`
-- against a new project). It is idempotent-ish (IF NOT EXISTS guards)
-- so it's safe to re-run while iterating.
--
-- Design goals baked into this schema:
--  1. Real, verifiable customer identity (customers.id == auth.users.id,
--     populated only via Supabase phone-OTP auth) — replaces the old
--     "type any phone number to see anyone's orders" behaviour.
--  2. Multi-image products (product_images), ordered, with a designated
--     primary/cover image.
--  3. Fast, typo-tolerant search (tsvector full-text + pg_trgm fuzzy
--     matching), so the app's search bar can find "swich" -> "switch".
--  4. Orders are only ever created by a SECURITY DEFINER function /
--     Edge Function that recomputes prices server-side — the app can
--     never insert an order row directly, so client-side price
--     tampering is impossible.
--  5. Row Level Security everywhere: customers only ever see their own
--     data, sellers are a named role (the `sellers` table) rather than
--     a hardcoded email, and everyone else gets read-only access to
--     public catalogue data.
-- =====================================================================

-- ---------- extensions ----------
create extension if not exists pgcrypto;      -- gen_random_uuid()
create extension if not exists pg_trgm;       -- fuzzy / typo-tolerant search
create extension if not exists unaccent;      -- accent-insensitive search

-- ---------- helper: updated_at trigger ----------
create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

-- =====================================================================
-- SELLERS  (who is allowed to manage the catalogue / fulfil orders)
-- =====================================================================
create table if not exists sellers (
  user_id     uuid primary key references auth.users(id) on delete cascade,
  name        text not null default 'Seller',
  created_at  timestamptz not null default now()
);
comment on table sellers is 'Marks an auth.users row as a store operator. Insert a row here (via SQL editor, once) for each seller/admin login you create.';

-- SECURITY DEFINER is required here: the `sellers` table has its own RLS
-- policy that itself calls is_seller() to decide who may read it. If this
-- function ran as the calling role (the default), that inner select would
-- be filtered by the very policy it's trying to evaluate — a real seller
-- would never be able to prove they're a seller. Running as the function
-- owner (bypassing RLS for this one, narrow, boolean-only lookup) breaks
-- that circularity safely, since the function can only ever return
-- true/false, never leak a row.
create or replace function is_seller()
returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from sellers where user_id = auth.uid());
$$;

-- =====================================================================
-- CUSTOMERS  (1:1 with auth.users, created after successful phone OTP)
-- =====================================================================
create table if not exists customers (
  id          uuid primary key references auth.users(id) on delete cascade,
  phone       text unique,            -- E.164, e.g. +919199156794
  name        text,
  email       text,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
drop trigger if exists trg_customers_updated on customers;
create trigger trg_customers_updated before update on customers
  for each row execute function set_updated_at();

-- Auto-create a blank customer profile the moment someone completes
-- phone-OTP sign-up, so the app never has to "ensure-customer" itself.
create or replace function handle_new_auth_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into customers (id, phone)
  values (new.id, new.phone)
  on conflict (id) do nothing;
  return new;
end;
$$;
drop trigger if exists trg_on_auth_user_created on auth.users;
create trigger trg_on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_auth_user();

-- =====================================================================
-- ADDRESSES
-- =====================================================================
create table if not exists addresses (
  id          uuid primary key default gen_random_uuid(),
  customer_id uuid not null references customers(id) on delete cascade,
  label       text not null default 'Home',       -- Home / Work / Other
  line1       text not null,
  line2       text,
  landmark    text,
  city        text not null default 'Hajipur',
  state       text not null default 'Bihar',
  pincode     text,
  lat         double precision,
  lng         double precision,
  is_default  boolean not null default false,
  created_at  timestamptz not null default now()
);
create index if not exists idx_addresses_customer on addresses(customer_id);

-- =====================================================================
-- CATALOGUE: brands / categories / products / product_images
-- =====================================================================
create table if not exists brands (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  slug        text not null unique,
  banner_url  text,
  description text,
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists categories (
  id          uuid primary key default gen_random_uuid(),
  slug        text not null unique,     -- e.g. 'lighting', 'fans'
  name        text not null,
  image_url   text,
  sort_order  int not null default 0,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

create table if not exists products (
  id               uuid primary key default gen_random_uuid(),
  sku              text unique,
  name             text not null,
  slug             text unique,
  brand_id         uuid references brands(id) on delete set null,
  brand_name       text,                 -- denormalized for fast search/display
  category_id      uuid references categories(id) on delete set null,
  price            numeric(10,2) not null check (price > 0),
  mrp              numeric(10,2) check (mrp is null or mrp >= price),
  stock            int not null default 0 check (stock >= 0),
  description      text,
  is_active        boolean not null default true,
  is_popular       boolean not null default false,
  coupon_eligible  boolean not null default true,
  avg_rating       numeric(2,1) not null default 0,
  rating_count     int not null default 0,
  search_vector    tsvector,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
drop trigger if exists trg_products_updated on products;
create trigger trg_products_updated before update on products
  for each row execute function set_updated_at();

-- keep brand_name in sync with brands.name so search_vector stays cheap
create or replace function sync_product_brand_name()
returns trigger language plpgsql as $$
begin
  if new.brand_id is not null then
    select name into new.brand_name from brands where id = new.brand_id;
  end if;
  return new;
end;
$$;
drop trigger if exists trg_products_brand_sync on products;
create trigger trg_products_brand_sync before insert or update of brand_id on products
  for each row execute function sync_product_brand_name();

-- full-text search vector: name weighted highest, then brand, then description
create or replace function products_search_vector_update()
returns trigger language plpgsql as $$
begin
  new.search_vector :=
    setweight(to_tsvector('english', unaccent(coalesce(new.name, ''))), 'A') ||
    setweight(to_tsvector('english', unaccent(coalesce(new.brand_name, ''))), 'B') ||
    setweight(to_tsvector('english', unaccent(coalesce(new.description, ''))), 'C');
  return new;
end;
$$;
drop trigger if exists trg_products_search_vector on products;
create trigger trg_products_search_vector
  before insert or update of name, brand_name, description on products
  for each row execute function products_search_vector_update();

create index if not exists idx_products_search on products using gin(search_vector);
create index if not exists idx_products_name_trgm on products using gin (name gin_trgm_ops);   -- fuzzy/typo-tolerant fallback
create index if not exists idx_products_brand_trgm on products using gin (brand_name gin_trgm_ops);
create index if not exists idx_products_category on products(category_id);
create index if not exists idx_products_active on products(is_active);

create table if not exists product_images (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references products(id) on delete cascade,
  url         text not null,
  sort_order  int not null default 0,      -- 0 = primary/cover image
  alt_text    text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_product_images_product on product_images(product_id, sort_order);

-- =====================================================================
-- DEALS  (homepage "today's deals")
-- =====================================================================
create table if not exists deals (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  category_id uuid references categories(id) on delete set null,
  img         text,
  start_date  date,
  end_date    date,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);

-- =====================================================================
-- COUPONS
-- =====================================================================
create table if not exists coupons (
  id               uuid primary key default gen_random_uuid(),
  code             text not null unique,
  title            text,
  scope            text not null default 'cart' check (scope in ('cart','category','product')),
  category_id      uuid references categories(id) on delete set null,
  product_id       uuid references products(id) on delete set null,
  discount_type    text not null check (discount_type in ('percent','flat')),
  discount_value   numeric(10,2) not null check (discount_value > 0),
  max_discount     numeric(10,2),
  min_order_value  numeric(10,2) not null default 0,
  starts_at        timestamptz,
  ends_at          timestamptz,
  is_active        boolean not null default true,
  created_at       timestamptz not null default now()
);

-- =====================================================================
-- ORDERS / ORDER_ITEMS
-- =====================================================================
create sequence if not exists order_code_seq;
create or replace function next_order_code()
returns text language sql as $$
  select 'RE' || to_char(now(), 'YYMMDD') || lpad(nextval('order_code_seq')::text, 4, '0');
$$;

create table if not exists orders (
  id               uuid primary key default gen_random_uuid(),
  order_code       text not null unique default next_order_code(),
  customer_id      uuid not null references customers(id),
  delivery_mode    text not null check (delivery_mode in ('delivery','pickup')),
  address_id       uuid references addresses(id),
  address_snapshot jsonb,                 -- frozen copy of the address at order time
  coupon_id        uuid references coupons(id),
  coupon_code      text,
  subtotal         numeric(10,2) not null,
  discount_total   numeric(10,2) not null default 0,
  cod_fee          numeric(10,2) not null default 0,
  grand_total      numeric(10,2) not null,
  payment_method   text not null check (payment_method in ('online','cod')),
  payment_status   text not null default 'pending' check (payment_status in ('pending','paid','failed','cancelled')),
  status           text not null default 'new' check (status in ('new','confirmed','in_transit','fulfilled','cancelled')),
  rzp_order_id     text,
  rzp_payment_id   text,
  created_at       timestamptz not null default now(),
  updated_at       timestamptz not null default now()
);
drop trigger if exists trg_orders_updated on orders;
create trigger trg_orders_updated before update on orders
  for each row execute function set_updated_at();
create index if not exists idx_orders_customer on orders(customer_id, created_at desc);
create index if not exists idx_orders_code on orders(order_code);

create table if not exists order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references orders(id) on delete cascade,
  product_id       uuid references products(id),
  product_name     text not null,          -- snapshot, survives product edits/deletes
  brand            text,
  category_id      uuid,
  unit_price       numeric(10,2) not null,
  qty              int not null check (qty > 0),
  line_total       numeric(10,2) not null,
  discount_amount  numeric(10,2) not null default 0,
  final_amount     numeric(10,2) not null
);
create index if not exists idx_order_items_order on order_items(order_id);

-- =====================================================================
-- REVIEWS + WISHLIST  (Flipkart-style extras)
-- =====================================================================
create table if not exists reviews (
  id          uuid primary key default gen_random_uuid(),
  product_id  uuid not null references products(id) on delete cascade,
  customer_id uuid not null references customers(id) on delete cascade,
  order_id    uuid references orders(id),     -- proof of purchase, optional
  rating      int not null check (rating between 1 and 5),
  comment     text,
  is_visible  boolean not null default true,
  created_at  timestamptz not null default now(),
  unique (product_id, customer_id)
);

create table if not exists wishlist (
  customer_id uuid not null references customers(id) on delete cascade,
  product_id  uuid not null references products(id) on delete cascade,
  created_at  timestamptz not null default now(),
  primary key (customer_id, product_id)
);

-- keep products.avg_rating / rating_count in sync
create or replace function refresh_product_rating()
returns trigger language plpgsql as $$
declare pid uuid;
begin
  pid := coalesce(new.product_id, old.product_id);
  update products p set
    avg_rating = coalesce((select round(avg(rating)::numeric, 1) from reviews where product_id = pid and is_visible), 0),
    rating_count = coalesce((select count(*) from reviews where product_id = pid and is_visible), 0)
  where p.id = pid;
  return null;
end;
$$;
drop trigger if exists trg_reviews_rating on reviews;
create trigger trg_reviews_rating
  after insert or update or delete on reviews
  for each row execute function refresh_product_rating();

-- =====================================================================
-- ROW LEVEL SECURITY
-- =====================================================================
alter table sellers enable row level security;
alter table customers enable row level security;
alter table addresses enable row level security;
alter table brands enable row level security;
alter table categories enable row level security;
alter table products enable row level security;
alter table product_images enable row level security;
alter table deals enable row level security;
alter table coupons enable row level security;
alter table orders enable row level security;
alter table order_items enable row level security;
alter table reviews enable row level security;
alter table wishlist enable row level security;

-- sellers: sellers can see the seller list (to render admin UI); nobody else can
drop policy if exists sellers_self_select on sellers;
create policy sellers_self_select on sellers for select using (is_seller());

-- customers: a customer can read/update only their own row; sellers can read all
drop policy if exists customers_self on customers;
create policy customers_self on customers for select using (id = auth.uid() or is_seller());
drop policy if exists customers_self_update on customers;
create policy customers_self_update on customers for update using (id = auth.uid());

-- addresses: customer manages their own; sellers can read all (for fulfilment)
drop policy if exists addresses_owner_all on addresses;
create policy addresses_owner_all on addresses for all
  using (customer_id = auth.uid() or is_seller())
  with check (customer_id = auth.uid());

-- catalogue tables: public read of active rows; sellers full read/write
drop policy if exists brands_public_read on brands;
create policy brands_public_read on brands for select using (is_active or is_seller());
drop policy if exists brands_seller_write on brands;
create policy brands_seller_write on brands for insert with check (is_seller());
drop policy if exists brands_seller_update on brands;
create policy brands_seller_update on brands for update using (is_seller());
drop policy if exists brands_seller_delete on brands;
create policy brands_seller_delete on brands for delete using (is_seller());

drop policy if exists categories_public_read on categories;
create policy categories_public_read on categories for select using (is_active or is_seller());
drop policy if exists categories_seller_write on categories;
create policy categories_seller_write on categories for insert with check (is_seller());
drop policy if exists categories_seller_update on categories;
create policy categories_seller_update on categories for update using (is_seller());
drop policy if exists categories_seller_delete on categories;
create policy categories_seller_delete on categories for delete using (is_seller());

drop policy if exists products_public_read on products;
create policy products_public_read on products for select using (is_active or is_seller());
drop policy if exists products_seller_write on products;
create policy products_seller_write on products for insert with check (is_seller());
drop policy if exists products_seller_update on products;
create policy products_seller_update on products for update using (is_seller());
drop policy if exists products_seller_delete on products;
create policy products_seller_delete on products for delete using (is_seller());

drop policy if exists product_images_public_read on product_images;
create policy product_images_public_read on product_images for select using (
  exists (select 1 from products p where p.id = product_id and (p.is_active or is_seller()))
);
drop policy if exists product_images_seller_write on product_images;
create policy product_images_seller_write on product_images for insert with check (is_seller());
drop policy if exists product_images_seller_update on product_images;
create policy product_images_seller_update on product_images for update using (is_seller());
drop policy if exists product_images_seller_delete on product_images;
create policy product_images_seller_delete on product_images for delete using (is_seller());

drop policy if exists deals_public_read on deals;
create policy deals_public_read on deals for select using (is_active or is_seller());
drop policy if exists deals_seller_write on deals;
create policy deals_seller_write on deals for insert with check (is_seller());
drop policy if exists deals_seller_update on deals;
create policy deals_seller_update on deals for update using (is_seller());
drop policy if exists deals_seller_delete on deals;
create policy deals_seller_delete on deals for delete using (is_seller());

drop policy if exists coupons_public_read on coupons;
create policy coupons_public_read on coupons for select using (is_active or is_seller());
drop policy if exists coupons_seller_write on coupons;
create policy coupons_seller_write on coupons for insert with check (is_seller());
drop policy if exists coupons_seller_update on coupons;
create policy coupons_seller_update on coupons for update using (is_seller());
drop policy if exists coupons_seller_delete on coupons;
create policy coupons_seller_delete on coupons for delete using (is_seller());

-- orders / order_items: customers see only their own; sellers see + update all.
-- NOTE: there is deliberately NO insert policy for plain authenticated users —
-- orders can only be created by the place-order Edge Function, which uses the
-- service-role key server-side. This is what stops a compromised or modified
-- client from ever writing an order (and its price) directly into the table.
drop policy if exists orders_owner_select on orders;
create policy orders_owner_select on orders for select using (customer_id = auth.uid() or is_seller());
drop policy if exists orders_seller_update on orders;
create policy orders_seller_update on orders for update using (is_seller());

drop policy if exists order_items_owner_select on order_items;
create policy order_items_owner_select on order_items for select using (
  exists (select 1 from orders o where o.id = order_id and (o.customer_id = auth.uid() or is_seller()))
);

-- reviews: anyone can read visible reviews; a customer can write only their own,
-- only for a product they actually have a fulfilled order for.
drop policy if exists reviews_public_read on reviews;
create policy reviews_public_read on reviews for select using (is_visible or is_seller());
drop policy if exists reviews_owner_write on reviews;
create policy reviews_owner_write on reviews for insert with check (
  customer_id = auth.uid()
  and exists (
    select 1 from orders o join order_items oi on oi.order_id = o.id
    where o.customer_id = auth.uid() and oi.product_id = reviews.product_id and o.status = 'fulfilled'
  )
);
drop policy if exists reviews_owner_update on reviews;
create policy reviews_owner_update on reviews for update using (customer_id = auth.uid() or is_seller());
drop policy if exists reviews_owner_delete on reviews;
create policy reviews_owner_delete on reviews for delete using (customer_id = auth.uid() or is_seller());

-- wishlist: fully private to the owning customer
drop policy if exists wishlist_owner_all on wishlist;
create policy wishlist_owner_all on wishlist for all
  using (customer_id = auth.uid())
  with check (customer_id = auth.uid());

-- =====================================================================
-- STORAGE: product image bucket
-- =====================================================================
insert into storage.buckets (id, name, public)
  values ('product-images', 'product-images', true)
  on conflict (id) do nothing;

drop policy if exists product_images_bucket_public_read on storage.objects;
create policy product_images_bucket_public_read on storage.objects
  for select using (bucket_id = 'product-images');

drop policy if exists product_images_bucket_seller_write on storage.objects;
create policy product_images_bucket_seller_write on storage.objects
  for insert with check (bucket_id = 'product-images' and is_seller());

drop policy if exists product_images_bucket_seller_update on storage.objects;
create policy product_images_bucket_seller_update on storage.objects
  for update using (bucket_id = 'product-images' and is_seller());

drop policy if exists product_images_bucket_seller_delete on storage.objects;
create policy product_images_bucket_seller_delete on storage.objects
  for delete using (bucket_id = 'product-images' and is_seller());

-- =====================================================================
-- SEARCH RPC — call this from the app instead of querying `products`
-- directly, so ranking/fuzzy-fallback logic lives in one place.
-- =====================================================================
create or replace function search_products(q text, cat_id uuid default null, limit_n int default 30, offset_n int default 0)
returns setof products
language sql stable as $$
  with fts as (
    select p.*, ts_rank(p.search_vector, websearch_to_tsquery('english', unaccent(q))) as rank
    from products p
    where p.is_active
      and (cat_id is null or p.category_id = cat_id)
      and p.search_vector @@ websearch_to_tsquery('english', unaccent(q))
  ),
  fuzzy as (
    -- word_similarity (the `<%` operator) matches a short/misspelled query
    -- against any WORD inside the product name/brand, e.g. "buld" -> "...Bulb...".
    -- Plain `similarity`/`%` compares whole strings and misses this case.
    select p.*, greatest(word_similarity(q, p.name), word_similarity(q, coalesce(p.brand_name,''))) as rank
    from products p
    where p.is_active
      and (cat_id is null or p.category_id = cat_id)
      and (q <% p.name or q <% coalesce(p.brand_name,''))
      and p.id not in (select id from fts)
  )
  select id, sku, name, slug, brand_id, brand_name, category_id, price, mrp, stock,
         description, is_active, is_popular, coupon_eligible, avg_rating, rating_count,
         search_vector, created_at, updated_at
  from (
    select * from fts
    union all
    select * from fuzzy
  ) combined
  order by rank desc
  limit limit_n offset offset_n;
$$;

-- =====================================================================
-- DONE. Next steps (see docs/BACKEND_SETUP.md):
--   1. Create a seller login: Authentication -> Add user (email/password),
--      then `insert into sellers (user_id, name) values ('<that user id>', 'Your Name');`
--   2. Enable Phone auth provider + an SMS provider (MSG91/Twilio) for
--      customer OTP login.
--   3. Deploy the Edge Functions in backend/functions/.
-- =====================================================================
