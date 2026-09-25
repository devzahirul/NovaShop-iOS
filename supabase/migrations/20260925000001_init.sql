-- NovaShop — Supabase schema, security and server-side business logic.
--
-- Design rules
--   • Catalog tables are public read-only.
--   • Every user-owned table has Row Level Security: a user can only ever touch rows where
--     user_id = auth.uid(). Policies use `(select auth.uid())` so Postgres evaluates it once per
--     statement (initPlan), not once per row.
--   • Clients never write orders, prices or stock. Checkout is ONE transactional function
--     (`place_order`) that reads prices from the database, locks and validates stock, applies the
--     coupon, and is idempotent — a retried request after a timeout can't create a second order.
--   • Secrets never ship in the app: the client only holds the publishable (anon) key; everything
--     privileged runs in SECURITY DEFINER functions with a pinned, empty search_path.

create extension if not exists pgcrypto;

-- ─────────────────────────────────────────────────────────────────────────────
-- Catalog (public, read-only)
-- ─────────────────────────────────────────────────────────────────────────────

create table public.categories (
  id          text primary key,
  name        text not null,
  image       text not null,
  styles      text[] not null default '{}',
  sort_order  int not null default 0
);

create table public.products (
  id                  text primary key,
  name                text not null,
  brand               text not null default 'NovaShop',
  price_cents         int  not null check (price_cents >= 0),
  compare_at_cents    int  check (compare_at_cents is null or compare_at_cents >= 0),
  category_id         text not null references public.categories (id),
  style               text not null default '',
  images              text[] not null default '{}',
  colors              jsonb not null default '[]',
  sizes               text[] not null default '{}',
  rating              numeric(2, 1) not null default 0,
  review_count        int not null default 0,
  rating_distribution jsonb not null default '{}',
  summary             text not null default '',
  details             text[] not null default '{}',
  tags                text[] not null default '{}',
  stock               int not null default 50 check (stock >= 0),
  in_stock            boolean generated always as (stock > 0) stored,
  released_at         timestamptz not null default now(),
  popularity          int not null default 0,
  sort_order          int not null default 0
);
create index products_category_idx on public.products (category_id);
create index products_tags_idx on public.products using gin (tags);

create table public.collections (
  id               text primary key,
  eyebrow          text not null,
  title            text not null,
  subtitle         text not null,
  cta_title        text not null,
  hero_image       text not null,
  editorial_images text[] not null default '{}',
  story_title      text not null,
  story_body       text not null,
  product_tag      text not null,
  sort_order       int not null default 0
);

create table public.reviews (
  id          text primary key,
  product_id  text not null references public.products (id) on delete cascade,
  author      text not null,
  rating      int  not null check (rating between 1 and 5),
  body        text not null,
  created_at  timestamptz not null default now(),
  is_verified boolean not null default false,
  photo_urls  text[] not null default '{}'
);
create index reviews_product_idx on public.reviews (product_id, created_at desc);

create table public.popular_searches (
  term       text primary key,
  sort_order int not null default 0
);

-- Coupons are never readable by clients; they're validated server-side.
create table public.coupons (
  code          text primary key,
  kind          text not null check (kind in ('percentage', 'fixed')),
  value         numeric(10, 2) not null check (value > 0),   -- 0.20 = 20 %, or dollars for 'fixed'
  minimum_cents int not null default 0,
  active        boolean not null default true
);

-- ─────────────────────────────────────────────────────────────────────────────
-- User data (RLS: owner only)
-- ─────────────────────────────────────────────────────────────────────────────

create table public.profiles (
  id                uuid primary key references auth.users (id) on delete cascade,
  full_name         text not null default '',
  style_preferences text[] not null default '{}',
  updated_at        timestamptz not null default now()
);

create table public.cart_items (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  line_key    text not null,                                 -- product|color|size, the client's stable id
  product_id  text not null references public.products (id) on delete cascade,
  color_name  text,
  size        text,
  quantity    int  not null check (quantity between 1 and 10),
  updated_at  timestamptz not null default now(),
  unique (user_id, line_key)
);

create table public.wishlist_items (
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  product_id text not null references public.products (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (user_id, product_id)
);

create table public.addresses (
  id          uuid primary key default gen_random_uuid(),
  user_id     uuid not null default auth.uid() references auth.users (id) on delete cascade,
  full_name   text not null check (length(trim(full_name)) > 0),
  line1       text not null check (length(trim(line1)) > 0),
  line2       text not null default '',
  city        text not null,
  state       text not null,
  postal_code text not null check (postal_code ~ '^\d{5}(-?\d{4})?$'),
  country     text not null default 'United States',
  is_default  boolean not null default false,
  created_at  timestamptz not null default now()
);
create unique index addresses_one_default on public.addresses (user_id) where is_default;

-- Only a tokenised reference is stored: brand + last four + expiry. Never a PAN or CVV.
create table public.payment_methods (
  id         uuid primary key default gen_random_uuid(),
  user_id    uuid not null default auth.uid() references auth.users (id) on delete cascade,
  brand      text not null,
  last4      text not null check (last4 ~ '^\d{4}$'),
  expiry     text not null check (expiry ~ '^\d{2}/\d{2}$'),
  holder     text not null,
  created_at timestamptz not null default now()
);

create sequence public.order_number_seq start 100001;

create table public.orders (
  id               uuid primary key default gen_random_uuid(),
  user_id          uuid not null references auth.users (id) on delete cascade,
  number           text not null unique,
  status           text not null default 'processing'
                   check (status in ('placed', 'processing', 'shipped', 'outForDelivery', 'delivered', 'cancelled')),
  shipping_option  text not null check (shipping_option in ('standard', 'express')),
  shipping_address jsonb not null,
  payment          jsonb not null,
  coupon_code      text,
  subtotal_cents   int not null,
  discount_cents   int not null,
  shipping_cents   int not null,
  tax_cents        int not null,
  total_cents      int not null,
  idempotency_key  uuid not null,
  placed_at        timestamptz not null default now(),
  unique (user_id, idempotency_key)
);
create index orders_user_idx on public.orders (user_id, placed_at desc);

create table public.order_items (
  id               uuid primary key default gen_random_uuid(),
  order_id         uuid not null references public.orders (id) on delete cascade,
  product_id       text not null references public.products (id),
  name             text not null,           -- snapshots: an order must not change when the catalog does
  image_url        text,
  color_name       text,
  color_hex        text,
  size             text,
  quantity         int not null check (quantity > 0),
  unit_price_cents int not null
);
create index order_items_order_idx on public.order_items (order_id);

create table public.notifications (
  id         text primary key default gen_random_uuid()::text,
  user_id    uuid references auth.users (id) on delete cascade,   -- null = broadcast
  kind       text not null check (kind in ('order', 'promotion', 'system')),
  title      text not null,
  body       text not null,
  is_read    boolean not null default false,
  created_at timestamptz not null default now()
);

-- ─────────────────────────────────────────────────────────────────────────────
-- Row Level Security
-- ─────────────────────────────────────────────────────────────────────────────

alter table public.categories       enable row level security;
alter table public.products         enable row level security;
alter table public.collections      enable row level security;
alter table public.reviews          enable row level security;
alter table public.popular_searches enable row level security;
alter table public.coupons          enable row level security;
alter table public.profiles         enable row level security;
alter table public.cart_items       enable row level security;
alter table public.wishlist_items   enable row level security;
alter table public.addresses        enable row level security;
alter table public.payment_methods  enable row level security;
alter table public.orders           enable row level security;
alter table public.order_items      enable row level security;
alter table public.notifications    enable row level security;

create policy "catalog: public read" on public.categories       for select to anon, authenticated using (true);
create policy "catalog: public read" on public.products         for select to anon, authenticated using (true);
create policy "catalog: public read" on public.collections      for select to anon, authenticated using (true);
create policy "catalog: public read" on public.reviews          for select to anon, authenticated using (true);
create policy "catalog: public read" on public.popular_searches for select to anon, authenticated using (true);
-- coupons: no policy at all → invisible to clients.

create policy "profiles: owner read"   on public.profiles for select to authenticated using (id = (select auth.uid()));
create policy "profiles: owner update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));

create policy "cart: owner only" on public.cart_items for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "wishlist: owner only" on public.wishlist_items for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "addresses: owner only" on public.addresses for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
create policy "payment methods: owner only" on public.payment_methods for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

-- Orders are read-only to their owner; they can only be created by place_order().
create policy "orders: owner read" on public.orders for select to authenticated using (user_id = (select auth.uid()));
create policy "order items: owner read" on public.order_items for select to authenticated
  using (exists (select 1 from public.orders o where o.id = order_id and o.user_id = (select auth.uid())));

create policy "notifications: own or broadcast" on public.notifications for select to anon, authenticated
  using (user_id is null or user_id = (select auth.uid()));

grant select on public.categories, public.products, public.collections, public.reviews,
                public.popular_searches, public.notifications to anon, authenticated;
grant select, update on public.profiles to authenticated;
grant select, insert, update, delete on public.cart_items, public.wishlist_items,
                public.addresses, public.payment_methods to authenticated;
grant select on public.orders, public.order_items to authenticated;
revoke all on public.coupons from anon, authenticated;
revoke insert, update, delete on public.orders, public.order_items from anon, authenticated;

-- ─────────────────────────────────────────────────────────────────────────────
-- Triggers
-- ─────────────────────────────────────────────────────────────────────────────

create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  insert into public.profiles (id, full_name)
  values (new.id, coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1)));
  return new;
end $$;

create trigger on_auth_user_created after insert on auth.users
  for each row execute function public.handle_new_user();

create function public.touch_updated_at() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger cart_items_touch before update on public.cart_items
  for each row execute function public.touch_updated_at();

-- Exactly one default address per user; the first address is always the default.
create function public.addresses_single_default() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.addresses where user_id = new.user_id and id <> new.id) then
    new.is_default := true;
  end if;
  if new.is_default then
    update public.addresses set is_default = false
    where user_id = new.user_id and id <> new.id and is_default;
  end if;
  return new;
end $$;

create trigger addresses_single_default before insert or update of is_default on public.addresses
  for each row execute function public.addresses_single_default();

create function public.addresses_promote_default() returns trigger
language plpgsql security definer set search_path = '' as $$
begin
  if old.is_default then
    update public.addresses set is_default = true
    where id = (select id from public.addresses where user_id = old.user_id order by created_at limit 1);
  end if;
  return null;
end $$;

create trigger addresses_promote_default after delete on public.addresses
  for each row execute function public.addresses_promote_default();

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: reads
-- ─────────────────────────────────────────────────────────────────────────────

-- Review page + server-side aggregate (the list is a page; the summary covers all reviews).
create function public.product_reviews(p_product_id text) returns jsonb
language sql stable set search_path = '' as $$
  select coalesce(
    (select jsonb_build_object(
       'summary', jsonb_build_object('average', p.rating, 'total', p.review_count, 'distribution', p.rating_distribution),
       'items', coalesce((
         select jsonb_agg(jsonb_build_object(
                  'id', r.id, 'product_id', r.product_id, 'author', r.author, 'rating', r.rating, 'body', r.body,
                  'date', r.created_at, 'is_verified', r.is_verified, 'photo_urls', r.photo_urls)
                order by r.created_at desc)
         from public.reviews r where r.product_id = p.id), '[]'::jsonb))
     from public.products p where p.id = p_product_id),
    '{"summary":{"average":0,"total":0,"distribution":{}},"items":[]}'::jsonb)
$$;

create function public.validate_coupon(p_code text, p_subtotal_cents int) returns jsonb
language plpgsql stable security definer set search_path = '' as $$
declare
  v_coupon public.coupons%rowtype;
begin
  select * into v_coupon from public.coupons where code = upper(trim(p_code)) and active;
  if not found then
    raise exception 'coupon_not_found' using errcode = 'P0001';
  end if;
  if p_subtotal_cents < v_coupon.minimum_cents then
    raise exception 'coupon_minimum_not_met' using errcode = 'P0001', detail = v_coupon.minimum_cents::text;
  end if;
  return jsonb_build_object('code', v_coupon.code, 'kind', v_coupon.kind, 'value', v_coupon.value,
                            'minimum_cents', v_coupon.minimum_cents);
end $$;

-- Canonical order JSON (one shape for place_order and my_orders).
create function public.order_json(p_order_id uuid) returns jsonb
language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'id', o.id, 'number', o.number, 'status', o.status, 'shipping_option', o.shipping_option,
    'shipping_address', o.shipping_address, 'payment', o.payment, 'coupon_code', o.coupon_code,
    'subtotal_cents', o.subtotal_cents, 'discount_cents', o.discount_cents, 'shipping_cents', o.shipping_cents,
    'tax_cents', o.tax_cents, 'total_cents', o.total_cents, 'placed_at', o.placed_at,
    'items', coalesce((
      select jsonb_agg(jsonb_build_object(
               'product_id', i.product_id, 'name', i.name, 'image_url', i.image_url, 'color_name', i.color_name,
               'color_hex', i.color_hex, 'size', i.size, 'quantity', i.quantity, 'unit_price_cents', i.unit_price_cents))
      from public.order_items i where i.order_id = o.id), '[]'::jsonb))
  from public.orders o
  where o.id = p_order_id and o.user_id = auth.uid()
$$;

create function public.my_orders() returns jsonb
language sql stable security definer set search_path = '' as $$
  select coalesce(jsonb_agg(public.order_json(o.id) order by o.placed_at desc), '[]'::jsonb)
  from public.orders o where o.user_id = auth.uid()
$$;

-- ─────────────────────────────────────────────────────────────────────────────
-- RPC: checkout — one transaction, server-authoritative pricing, idempotent
-- ─────────────────────────────────────────────────────────────────────────────

create function public.place_order(
  p_address_id      uuid,
  p_shipping        text,
  p_payment         jsonb,
  p_idempotency_key uuid,
  p_coupon          text default null
) returns jsonb
language plpgsql security definer set search_path = '' as $$
declare
  v_user      uuid := auth.uid();
  v_order_id  uuid;
  v_address   public.addresses%rowtype;
  v_coupon    public.coupons%rowtype;
  v_lines     int;
  v_subtotal  int;
  v_discount  int := 0;
  v_shipping  int;
  v_tax       int;
  v_short     text;
begin
  if v_user is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;

  -- Idempotency: the same key always returns the same order (safe to retry after a timeout).
  select id into v_order_id from public.orders where user_id = v_user and idempotency_key = p_idempotency_key;
  if found then
    return public.order_json(v_order_id);
  end if;

  select * into v_address from public.addresses where id = p_address_id and user_id = v_user;
  if not found then
    raise exception 'address_not_found' using errcode = 'P0001';
  end if;

  v_shipping := case p_shipping when 'standard' then 0 when 'express' then 1200 end;
  if v_shipping is null then
    raise exception 'invalid_shipping' using errcode = 'P0001';
  end if;

  -- Demo payment processor: the test card ending 0002 is always declined.
  if p_payment ->> 'last4' = '0002' then
    raise exception 'payment_declined' using errcode = 'P0001';
  end if;

  -- Lock the products being bought, in a stable order (avoids deadlocks between concurrent checkouts).
  perform 1 from public.products
  where id in (select product_id from public.cart_items where user_id = v_user)
  order by id
  for update;

  select count(*), coalesce(sum(ci.quantity * p.price_cents), 0)
  into v_lines, v_subtotal
  from public.cart_items ci join public.products p on p.id = ci.product_id
  where ci.user_id = v_user;

  if v_lines = 0 then
    raise exception 'cart_empty' using errcode = 'P0001';
  end if;

  select string_agg(p.name, ', ') into v_short
  from (select product_id, sum(quantity) as qty from public.cart_items where user_id = v_user group by product_id) c
  join public.products p on p.id = c.product_id
  where p.stock < c.qty;

  if v_short is not null then
    raise exception 'out_of_stock' using errcode = 'P0001', detail = v_short;
  end if;

  if coalesce(trim(p_coupon), '') <> '' then
    select * into v_coupon from public.coupons where code = upper(trim(p_coupon)) and active;
    if not found then
      raise exception 'coupon_not_found' using errcode = 'P0001';
    end if;
    if v_subtotal < v_coupon.minimum_cents then
      raise exception 'coupon_minimum_not_met' using errcode = 'P0001', detail = v_coupon.minimum_cents::text;
    end if;
    v_discount := case v_coupon.kind
      when 'percentage' then round(v_subtotal * v_coupon.value)::int
      else least(round(v_coupon.value * 100)::int, v_subtotal)
    end;
  end if;

  v_tax := round((v_subtotal - v_discount) * 0.0825)::int;

  insert into public.orders (
    user_id, number, shipping_option, shipping_address, payment, coupon_code,
    subtotal_cents, discount_cents, shipping_cents, tax_cents, total_cents, idempotency_key)
  values (
    v_user,
    'NS' || nextval('public.order_number_seq'),
    p_shipping,
    jsonb_build_object('id', v_address.id, 'full_name', v_address.full_name, 'line1', v_address.line1,
                       'line2', v_address.line2, 'city', v_address.city, 'state', v_address.state,
                       'postal_code', v_address.postal_code, 'country', v_address.country, 'is_default', v_address.is_default),
    -- Whitelist: never persist anything but a display-safe reference.
    jsonb_build_object('id', coalesce(p_payment ->> 'id', gen_random_uuid()::text), 'kind', p_payment ->> 'kind',
                       'brand', p_payment ->> 'brand', 'last4', p_payment ->> 'last4',
                       'expiry', p_payment ->> 'expiry', 'holder', p_payment ->> 'holder'),
    nullif(upper(trim(p_coupon)), ''),
    v_subtotal, v_discount, v_shipping, v_tax, v_subtotal - v_discount + v_shipping + v_tax,
    p_idempotency_key)
  returning id into v_order_id;

  insert into public.order_items (order_id, product_id, name, image_url, color_name, color_hex, size, quantity, unit_price_cents)
  select v_order_id, p.id, p.name, p.images[1], ci.color_name,
         (select c ->> 'hex' from jsonb_array_elements(p.colors) c where c ->> 'name' = ci.color_name limit 1),
         ci.size, ci.quantity, p.price_cents
  from public.cart_items ci join public.products p on p.id = ci.product_id
  where ci.user_id = v_user;

  update public.products p set stock = p.stock - c.qty
  from (select product_id, sum(quantity) as qty from public.cart_items where user_id = v_user group by product_id) c
  where p.id = c.product_id;

  delete from public.cart_items where user_id = v_user;

  insert into public.notifications (user_id, kind, title, body)
  select v_user, 'order', 'Order placed', 'Order #' || number || ' is being prepared.'
  from public.orders where id = v_order_id;

  return public.order_json(v_order_id);
end $$;

-- In-app account deletion (App Store guideline 5.1.1(v)) without shipping an admin key.
create function public.delete_my_account() returns void
language plpgsql security definer set search_path = '' as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '28000';
  end if;
  delete from auth.users where id = auth.uid();
end $$;

-- Function privileges: nothing is callable by default; grant exactly what the app needs.
revoke execute on all functions in schema public from public, anon, authenticated;
grant execute on function public.product_reviews(text)            to anon, authenticated;
grant execute on function public.validate_coupon(text, int)       to anon, authenticated;
grant execute on function public.my_orders()                      to authenticated;
grant execute on function public.place_order(uuid, text, jsonb, uuid, text) to authenticated;
grant execute on function public.delete_my_account()              to authenticated;
