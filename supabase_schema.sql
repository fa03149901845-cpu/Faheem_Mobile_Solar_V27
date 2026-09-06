-- Faheem Mobile and Solar Electronics - V5 secure backend
create extension if not exists pgcrypto;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  full_name text,
  role text not null default 'customer' check (role in ('customer','admin')),
  created_at timestamptz not null default now()
);
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(), name text not null, description text default '',
  category text not null, price numeric(12,2) not null check (price >= 0), image text,
  active boolean not null default true, stock integer not null default 0 check (stock >= 0), created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);

-- V10 migration: inventory stock. Safe to run on an existing V5-V9 database.
alter table public.products add column if not exists stock integer not null default 0;
alter table public.products drop constraint if exists products_stock_check;
alter table public.products add constraint products_stock_check check (stock >= 0);

create table if not exists public.orders (
  id uuid primary key default gen_random_uuid(), order_number text unique not null,
  user_id uuid not null references auth.users(id) on delete restrict, customer_name text not null,
  phone text not null, city text not null, area text, address text not null, notes text,
  payment_method text not null default 'Cash on Delivery', total numeric(12,2) not null check (total >= 0),
  status text not null default 'Pending' check (status in ('Pending','Confirmed','Packed','Shipped','Delivered','Cancelled')),
  created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table if not exists public.order_items (
  id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete cascade,
  product_id uuid references public.products(id) on delete set null, product_name text not null,
  quantity integer not null check (quantity > 0), unit_price numeric(12,2) not null check (unit_price >= 0),
  subtotal numeric(12,2) not null check (subtotal >= 0)
);

create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin insert into public.profiles(id,full_name) values(new.id,new.raw_user_meta_data->>'full_name') on conflict(id) do nothing; return new; end; $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.profiles where id=auth.uid() and role='admin');
$$;

alter table public.profiles enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists "profiles own read" on public.profiles;
create policy "profiles own read" on public.profiles for select using (id=auth.uid() or public.is_admin());
drop policy if exists "profiles own update" on public.profiles;
create policy "profiles own update" on public.profiles for update using (id=auth.uid()) with check (id=auth.uid());
drop policy if exists "products public read active" on public.products;
create policy "products public read active" on public.products for select using (active=true or public.is_admin());
drop policy if exists "products admin insert" on public.products;
create policy "products admin insert" on public.products for insert with check (public.is_admin());
drop policy if exists "products admin update" on public.products;
create policy "products admin update" on public.products for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "products admin delete" on public.products;
create policy "products admin delete" on public.products for delete using (public.is_admin());
drop policy if exists "orders own read" on public.orders;
create policy "orders own read" on public.orders for select using (user_id=auth.uid() or public.is_admin());
-- Direct client INSERT is intentionally disabled; customers create orders through create_order_secure().
drop policy if exists "orders customer insert" on public.orders;
drop policy if exists "orders admin update" on public.orders;
create policy "orders admin update" on public.orders for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "items own read" on public.order_items;
create policy "items own read" on public.order_items for select using (exists(select 1 from public.orders o where o.id=order_id and (o.user_id=auth.uid() or public.is_admin())));
drop policy if exists "items customer insert" on public.order_items;

-- Transactional server-side order creation: validates the signed-in user, reads authoritative prices,
-- computes the total, creates the order and its items atomically, and never trusts browser totals/prices.
create or replace function public.create_order_secure(
  p_customer_name text, p_phone text, p_city text, p_area text, p_address text,
  p_notes text, p_payment_method text, p_items jsonb
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid; v_order_number text; v_total numeric(12,2); item jsonb; v_product public.products%rowtype; v_qty integer;
begin
  if auth.uid() is null then raise exception 'You must be signed in to place an order'; end if;
  if coalesce(length(trim(p_customer_name)),0)=0 or coalesce(length(trim(p_phone)),0)=0 or coalesce(length(trim(p_city)),0)=0 or coalesce(length(trim(p_address)),0)=0 then
    raise exception 'Customer name, phone, city and address are required';
  end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Cart is empty'; end if;
  v_total:=0;
  for item in select * from jsonb_array_elements(p_items) loop
    if nullif(item->>'product_id','') is null then raise exception 'Invalid product'; end if;
    v_qty:=(item->>'quantity')::integer;
    if v_qty < 1 then raise exception 'Invalid quantity'; end if;
    select * into v_product from public.products where id=(item->>'product_id')::uuid and active=true for update;
    if not found then raise exception 'Product is unavailable'; end if;
    if v_product.stock < v_qty then raise exception 'Insufficient stock for: % (available: %)',v_product.name,v_product.stock; end if;
    v_total:=v_total+(v_product.price*v_qty);
  end loop;
  v_order_number:='FME-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.orders(order_number,user_id,customer_name,phone,city,area,address,notes,payment_method,total)
  values(v_order_number,auth.uid(),trim(p_customer_name),trim(p_phone),trim(p_city),nullif(trim(p_area),''),trim(p_address),nullif(trim(p_notes),''),coalesce(nullif(trim(p_payment_method),''),'Cash on Delivery'),v_total)
  returning id into v_order_id;
  for item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(item->>'quantity')::integer;
    select * into v_product from public.products where id=(item->>'product_id')::uuid and active=true for update;
    update public.products set stock=stock-v_qty,updated_at=now() where id=v_product.id and stock>=v_qty;
    if not found then raise exception 'Insufficient stock for: %',v_product.name; end if;
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,subtotal)
    values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price,v_product.price*v_qty);
  end loop;
  return jsonb_build_object('id',v_order_id,'order_number',v_order_number,'total',v_total);
end; $$;
revoke all on function public.create_order_secure(text,text,text,text,text,text,text,jsonb) from public;
grant execute on function public.create_order_secure(text,text,text,text,text,text,text,jsonb) to authenticated;

insert into public.products(name,description,category,price)
select * from (values
 ('Longi 550W Solar Panel Mono PERC','High-efficiency 550W solar panel.','solar-panels',24999::numeric,10),
 ('Inverex Nitrox 6KW Hybrid Solar Inverter','6KW hybrid solar inverter.','inverters',165000::numeric,5),
 ('Osaka 200Ah Solar Battery Tall Tubular','200Ah tall tubular battery.','batteries',45000::numeric,8),
 ('Solar DC Cable 6mm (Price Per Meter)','6mm solar DC cable, price per meter.','cables',180::numeric,100),
 ('LED Bulb 20W Energy Saver','20W energy-saving LED bulb.','lighting',350::numeric,25)
) v(name,description,category,price,stock) where not exists(select 1 from public.products);

-- After creating your own account through the website, promote it once:
-- update public.profiles set role='admin' where id=(select id from auth.users where email='YOUR_ADMIN_EMAIL');

-- V11: customer profile/address fields + managed categories + secure product image storage
alter table public.profiles add column if not exists phone text;
alter table public.profiles add column if not exists city text;
alter table public.profiles add column if not exists area text;
alter table public.profiles add column if not exists address text;

create table if not exists public.categories (
  id uuid primary key default gen_random_uuid(),
  name text unique not null,
  slug text unique not null,
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.categories enable row level security;
drop policy if exists "categories public active read" on public.categories;
create policy "categories public active read" on public.categories for select using (active=true or public.is_admin());
drop policy if exists "categories admin insert" on public.categories;
create policy "categories admin insert" on public.categories for insert with check (public.is_admin());
drop policy if exists "categories admin update" on public.categories;
create policy "categories admin update" on public.categories for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "categories admin delete" on public.categories;
create policy "categories admin delete" on public.categories for delete using (public.is_admin());

insert into public.categories(name,slug) values
('Solar Panels','solar-panels'),('Inverters','inverters'),('Batteries','batteries'),('Cables','cables'),('Mobile Accessories','mobile'),('Lighting','lighting'),('Other','other')
on conflict (slug) do nothing;

insert into storage.buckets(id,name,public) values ('product-images','product-images',true)
on conflict (id) do update set public=true;
drop policy if exists "product images public read" on storage.objects;
create policy "product images public read" on storage.objects for select using (bucket_id='product-images');
drop policy if exists "product images admin upload" on storage.objects;
create policy "product images admin upload" on storage.objects for insert to authenticated with check (bucket_id='product-images' and public.is_admin());
drop policy if exists "product images admin update" on storage.objects;
create policy "product images admin update" on storage.objects for update to authenticated using (bucket_id='product-images' and public.is_admin()) with check (bucket_id='product-images' and public.is_admin());
drop policy if exists "product images admin delete" on storage.objects;
create policy "product images admin delete" on storage.objects for delete to authenticated using (bucket_id='product-images' and public.is_admin());


alter table public.orders add column if not exists coupon_code text;
alter table public.orders add column if not exists discount numeric(12,2) not null default 0;

-- V12: categories, coupons, and customer address book
create table if not exists public.coupons (
 id uuid primary key default gen_random_uuid(), code text unique not null,
 type text not null check (type in ('percent','fixed')), value numeric(12,2) not null check (value>0),
 min_order numeric(12,2) not null default 0 check (min_order>=0), usage_limit integer,
 used_count integer not null default 0 check (used_count>=0), active boolean not null default true,
 created_at timestamptz not null default now()
);
create table if not exists public.addresses (
 id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
 label text not null default 'Address', city text not null, area text, address text not null,
 is_default boolean not null default false, created_at timestamptz not null default now()
);
alter table public.coupons enable row level security;
alter table public.addresses enable row level security;
drop policy if exists "coupons admin read" on public.coupons;
create policy "coupons admin read" on public.coupons for select using (public.is_admin());
drop policy if exists "coupons admin insert" on public.coupons;
create policy "coupons admin insert" on public.coupons for insert with check (public.is_admin());
drop policy if exists "coupons admin update" on public.coupons;
create policy "coupons admin update" on public.coupons for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "addresses own read" on public.addresses;
create policy "addresses own read" on public.addresses for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists "addresses own insert" on public.addresses;
create policy "addresses own insert" on public.addresses for insert with check (user_id=auth.uid());
drop policy if exists "addresses own update" on public.addresses;
create policy "addresses own update" on public.addresses for update using (user_id=auth.uid()) with check (user_id=auth.uid());
drop policy if exists "addresses own delete" on public.addresses;
create policy "addresses own delete" on public.addresses for delete using (user_id=auth.uid());
create or replace function public.validate_coupon(p_code text,p_order_total numeric) returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.coupons%rowtype; d numeric;
begin
 if auth.uid() is null then raise exception 'You must be signed in'; end if;
 select * into c from public.coupons where code=upper(trim(p_code)) and active=true for update;
 if not found then raise exception 'Invalid or inactive coupon'; end if;
 if c.usage_limit is not null and c.used_count>=c.usage_limit then raise exception 'Coupon usage limit reached'; end if;
 if p_order_total < c.min_order then raise exception 'Minimum order is Rs. %',c.min_order; end if;
 d:=case when c.type='percent' then round(p_order_total*c.value/100,2) else least(c.value,p_order_total) end;
 return jsonb_build_object('code',c.code,'discount',d,'discount_text',case when c.type='percent' then c.value||'% off' else 'Rs. '||d||' off' end);
end; $$;
revoke all on function public.validate_coupon(text,numeric) from public;
grant execute on function public.validate_coupon(text,numeric) to authenticated;


-- V13: secure coupon application during order creation
create or replace function public.create_order_secure(
  p_customer_name text, p_phone text, p_city text, p_area text, p_address text,
  p_notes text, p_payment_method text, p_items jsonb, p_coupon_code text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  v_order_id uuid; v_order_number text; v_subtotal numeric(12,2):=0; v_discount numeric(12,2):=0; v_total numeric(12,2);
  item jsonb; v_product public.products%rowtype; v_qty integer; c public.coupons%rowtype;
begin
  if auth.uid() is null then raise exception 'You must be signed in to place an order'; end if;
  if coalesce(length(trim(p_customer_name)),0)=0 or coalesce(length(trim(p_phone)),0)=0 or coalesce(length(trim(p_city)),0)=0 or coalesce(length(trim(p_address)),0)=0 then raise exception 'Customer name, phone, city and address are required'; end if;
  if jsonb_typeof(p_items) <> 'array' or jsonb_array_length(p_items)=0 then raise exception 'Cart is empty'; end if;
  for item in select * from jsonb_array_elements(p_items) loop
    if nullif(item->>'product_id','') is null then raise exception 'Invalid product'; end if;
    v_qty:=(item->>'quantity')::integer; if v_qty<1 then raise exception 'Invalid quantity'; end if;
    select * into v_product from public.products where id=(item->>'product_id')::uuid and active=true for update;
    if not found then raise exception 'Product is unavailable'; end if;
    if v_product.stock<v_qty then raise exception 'Insufficient stock for: % (available: %)',v_product.name,v_product.stock; end if;
    v_subtotal:=v_subtotal+(v_product.price*v_qty);
  end loop;
  if nullif(trim(p_coupon_code),'') is not null then
    select * into c from public.coupons where code=upper(trim(p_coupon_code)) and active=true for update;
    if not found then raise exception 'Invalid or inactive coupon'; end if;
    if c.usage_limit is not null and c.used_count>=c.usage_limit then raise exception 'Coupon usage limit reached'; end if;
    if v_subtotal<c.min_order then raise exception 'Minimum order is Rs. %',c.min_order; end if;
    v_discount:=case when c.type='percent' then round(v_subtotal*c.value/100,2) else least(c.value,v_subtotal) end;
  end if;
  v_total:=greatest(v_subtotal-v_discount,0);
  v_order_number:='FME-'||upper(substr(replace(gen_random_uuid()::text,'-',''),1,8));
  insert into public.orders(order_number,user_id,customer_name,phone,city,area,address,notes,payment_method,total,coupon_code,discount)
  values(v_order_number,auth.uid(),trim(p_customer_name),trim(p_phone),trim(p_city),nullif(trim(p_area),''),trim(p_address),nullif(trim(p_notes),''),coalesce(nullif(trim(p_payment_method),''),'Cash on Delivery'),v_total,nullif(upper(trim(p_coupon_code)),''),v_discount) returning id into v_order_id;
  for item in select * from jsonb_array_elements(p_items) loop
    v_qty:=(item->>'quantity')::integer; select * into v_product from public.products where id=(item->>'product_id')::uuid and active=true for update;
    update public.products set stock=stock-v_qty,updated_at=now() where id=v_product.id and stock>=v_qty; if not found then raise exception 'Insufficient stock for: %',v_product.name; end if;
    insert into public.order_items(order_id,product_id,product_name,quantity,unit_price,subtotal) values(v_order_id,v_product.id,v_product.name,v_qty,v_product.price,v_product.price*v_qty);
  end loop;
  if c.id is not null then update public.coupons set used_count=used_count+1 where id=c.id; end if;
  return jsonb_build_object('id',v_order_id,'order_number',v_order_number,'subtotal',v_subtotal,'discount',v_discount,'total',v_total,'coupon_code',nullif(upper(trim(p_coupon_code)),''));
end; $$;
revoke all on function public.create_order_secure(text,text,text,text,text,text,text,jsonb) from public;
revoke all on function public.create_order_secure(text,text,text,text,text,text,text,jsonb,text) from public;
grant execute on function public.create_order_secure(text,text,text,text,text,text,text,jsonb,text) to authenticated;

-- V14: admin customers, advanced order/payment tracking, and store settings
alter table public.orders add column if not exists payment_status text not null default 'Pending';
alter table public.orders add column if not exists tracking_number text;
alter table public.orders add column if not exists delivery_note text;
alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check check (payment_status in ('Pending','Verified','Failed','Refunded'));

create index if not exists orders_user_created_idx on public.orders(user_id,created_at desc);
create index if not exists orders_status_idx on public.orders(status);
create index if not exists orders_payment_status_idx on public.orders(payment_status);

-- Admin-only customer summary. Email is read from auth.users server-side so it is never exposed by a client-side query.
create or replace function public.admin_customer_summary() returns table(
  id uuid, email text, full_name text, phone text, city text, area text, address text,
  role text, created_at timestamptz, order_count bigint, total_spend numeric
) language sql security definer set search_path=public,auth as $$
  select p.id, u.email, p.full_name, p.phone, p.city, p.area, p.address, p.role, p.created_at,
         count(o.id)::bigint as order_count,
         coalesce(sum(case when o.status <> 'Cancelled' then o.total else 0 end),0)::numeric as total_spend
  from public.profiles p
  join auth.users u on u.id=p.id
  left join public.orders o on o.user_id=p.id
  where public.is_admin()
  group by p.id,u.email,p.full_name,p.phone,p.city,p.area,p.address,p.role,p.created_at
  order by p.created_at desc;
$$;
revoke all on function public.admin_customer_summary() from public;
grant execute on function public.admin_customer_summary() to authenticated;

create table if not exists public.store_settings (
  key text primary key,
  value text not null default '',
  updated_at timestamptz not null default now()
);
alter table public.store_settings enable row level security;
drop policy if exists "store settings public read" on public.store_settings;
create policy "store settings public read" on public.store_settings for select using (true);
drop policy if exists "store settings admin insert" on public.store_settings;
create policy "store settings admin insert" on public.store_settings for insert with check (public.is_admin());
drop policy if exists "store settings admin update" on public.store_settings;
create policy "store settings admin update" on public.store_settings for update using (public.is_admin()) with check (public.is_admin());
drop policy if exists "store settings admin delete" on public.store_settings;
create policy "store settings admin delete" on public.store_settings for delete using (public.is_admin());

insert into public.store_settings(key,value) values
('store_name','Faheem Mobile and Solar Electronics'),
('whatsapp','923001234567'),
('phone','+92 300 1234567'),
('email','faheemmobileandsolar@gmail.com'),
('city','Your City'),
('address','Main Road, Your City, Pakistan'),
('currency','Rs.'),
('cod_enabled','true')
on conflict (key) do nothing;

-- V14 cleanup: remove the legacy 8-parameter order RPC; V13+ uses the coupon-aware version only.
drop function if exists public.create_order_secure(text,text,text,text,text,text,text,jsonb);



-- ============================================================
-- V15: Delivery management, order timeline and notification hooks
-- ============================================================
alter table public.orders add column if not exists payment_status text not null default 'pending';
alter table public.orders add column if not exists tracking_number text;
alter table public.orders add column if not exists shipping_provider text;
alter table public.orders add column if not exists estimated_delivery date;
alter table public.orders add column if not exists delivered_at timestamptz;

do $$ begin
  alter table public.orders drop constraint if exists orders_payment_status_check;
  alter table public.orders add constraint orders_payment_status_check check (payment_status in ('pending','verified','failed','refunded'));
exception when others then null; end $$;

do $$ begin
  alter table public.orders drop constraint if exists orders_status_check;
  alter table public.orders add constraint orders_status_check check (status in ('pending','confirmed','packed','shipped','out_for_delivery','delivered','cancelled'));
exception when others then null; end $$;

create table if not exists public.order_timeline (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status text not null,
  note text,
  changed_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

alter table public.order_timeline enable row level security;
drop policy if exists "timeline customer read" on public.order_timeline;
drop policy if exists "timeline admin all" on public.order_timeline;
create policy "timeline customer read" on public.order_timeline for select to authenticated
using (exists (select 1 from public.orders o where o.id=order_timeline.order_id and o.user_id=auth.uid()));
create policy "timeline admin all" on public.order_timeline for all to authenticated using (public.is_admin()) with check (public.is_admin());

create index if not exists order_timeline_order_id_created_idx on public.order_timeline(order_id, created_at desc);
create index if not exists orders_tracking_number_idx on public.orders(tracking_number);

-- Server-side admin order update + timeline entry.
create or replace function public.admin_update_order_tracking(
  p_order_id uuid,
  p_status text default null,
  p_payment_status text default null,
  p_tracking_number text default null,
  p_shipping_provider text default null,
  p_estimated_delivery date default null,
  p_note text default null
) returns public.orders
language plpgsql security definer set search_path=public
as $$
declare v_order public.orders;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  if p_status is not null and p_status not in ('pending','confirmed','packed','shipped','out_for_delivery','delivered','cancelled') then raise exception 'invalid status'; end if;
  if p_payment_status is not null and p_payment_status not in ('pending','verified','failed','refunded') then raise exception 'invalid payment status'; end if;
  update public.orders set
    status=coalesce(p_status,status),
    payment_status=coalesce(p_payment_status,payment_status),
    tracking_number=coalesce(nullif(trim(p_tracking_number),''),tracking_number),
    shipping_provider=coalesce(nullif(trim(p_shipping_provider),''),shipping_provider),
    estimated_delivery=coalesce(p_estimated_delivery,estimated_delivery),
    delivered_at=case when p_status='delivered' then coalesce(delivered_at,now()) when p_status is not null and p_status<>'delivered' then null else delivered_at end,
    updated_at=now()
  where id=p_order_id returning * into v_order;
  if not found then raise exception 'order not found'; end if;
  if p_status is not null or p_note is not null then
    insert into public.order_timeline(order_id,status,note,changed_by)
    values(v_order.id,coalesce(p_status,v_order.status),nullif(trim(p_note),''),auth.uid());
  end if;
  return v_order;
end $$;
revoke all on function public.admin_update_order_tracking(uuid,text,text,text,text,date,text) from public;
grant execute on function public.admin_update_order_tracking(uuid,text,text,text,text,date,text) to authenticated;

-- Seed a timeline entry for existing orders where possible.
insert into public.order_timeline(order_id,status,note)
select o.id,o.status,'Imported from existing order history'
from public.orders o
where not exists (select 1 from public.order_timeline t where t.order_id=o.id);

-- ============================================================
-- V16: Customer experience, notifications, payment reference
-- ============================================================
alter table public.orders add column if not exists payment_reference text;
create index if not exists orders_payment_reference_idx on public.orders(payment_reference);

create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  order_id uuid references public.orders(id) on delete cascade,
  title text not null,
  message text not null,
  read_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.notifications enable row level security;
drop policy if exists "notifications customer read" on public.notifications;
create policy "notifications customer read" on public.notifications for select to authenticated using (user_id=auth.uid());
drop policy if exists "notifications customer update" on public.notifications;
create policy "notifications customer update" on public.notifications for update to authenticated using (user_id=auth.uid()) with check (user_id=auth.uid());
drop policy if exists "notifications admin read" on public.notifications;
create policy "notifications admin read" on public.notifications for select to authenticated using (public.is_admin());
create index if not exists notifications_user_created_idx on public.notifications(user_id,created_at desc);

-- Extended secure order RPC: keeps the existing authoritative pricing/stock/coupon logic and
-- records an optional payment transaction reference. Payment method is validated server-side.
create or replace function public.create_order_secure(
  p_customer_name text, p_phone text, p_city text, p_area text, p_address text,
  p_notes text, p_payment_method text, p_items jsonb, p_coupon_code text default null,
  p_payment_reference text default null
) returns jsonb language plpgsql security definer set search_path=public as $$
declare
  r jsonb; v_id uuid; v_cod text; v_method text;
begin
  if auth.uid() is null then raise exception 'You must be signed in to place an order'; end if;
  v_method:=coalesce(nullif(trim(p_payment_method),''),'Cash on Delivery');
  select value into v_cod from public.store_settings where key='cod_enabled';
  if lower(v_method)='cash on delivery' and coalesce(lower(v_cod),'true')<>'true' then raise exception 'Cash on Delivery is disabled'; end if;
  if lower(v_method) not in ('cash on delivery','bank transfer','easypaisa / jazzcash') then raise exception 'Invalid payment method'; end if;
  r:=public.create_order_secure(p_customer_name,p_phone,p_city,p_area,p_address,p_notes,v_method,p_items,p_coupon_code);
  v_id:=(r->>'id')::uuid;
  update public.orders set invoice_number=coalesce(invoice_number,public.next_invoice_number()), payment_reference=nullif(trim(p_payment_reference),''), updated_at=now() where id=v_id and user_id=auth.uid();
  return r || jsonb_build_object('payment_reference',nullif(trim(p_payment_reference),''));
end; $$;
revoke all on function public.create_order_secure(text,text,text,text,text,text,text,jsonb,text,text) from public;
grant execute on function public.create_order_secure(text,text,text,text,text,text,text,jsonb,text,text) to authenticated;

-- Admin-only notification creator. The browser never supplies user_id; it is derived from the order.
create or replace function public.admin_create_order_notification(
  p_order_id uuid, p_title text, p_message text
) returns public.notifications language plpgsql security definer set search_path=public as $$
declare n public.notifications;
begin
  if not public.is_admin() then raise exception 'admin only'; end if;
  insert into public.notifications(user_id,order_id,title,message)
  select o.user_id,p_order_id,left(trim(p_title),120),left(trim(p_message),1000)
  from public.orders o where o.id=p_order_id returning * into n;
  if not found then raise exception 'order not found'; end if;
  return n;
end; $$;
revoke all on function public.admin_create_order_notification(uuid,text,text) from public;
grant execute on function public.admin_create_order_notification(uuid,text,text) to authenticated;

-- Automatic customer notifications for important order/payment transitions.
create or replace function public.orders_v16_notify() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if TG_OP='INSERT' then
    insert into public.order_timeline(order_id,status,note,changed_by) values(new.id,new.status,'Order placed',new.user_id);
    insert into public.notifications(user_id,order_id,title,message) values(new.user_id,new.id,'Order received','Your order '||new.order_number||' has been received and is pending confirmation.');
  elsif TG_OP='UPDATE' then
    if new.status is distinct from old.status then
      insert into public.order_timeline(order_id,status,note,changed_by) values(new.id,new.status,'Order status changed',auth.uid());
      insert into public.notifications(user_id,order_id,title,message) values(new.user_id,new.id,'Order status updated','Order '||new.order_number||' is now '||replace(initcap(new.status),'_',' ')||'.');
    end if;
    if new.payment_status is distinct from old.payment_status then
      insert into public.notifications(user_id,order_id,title,message) values(new.user_id,new.id,'Payment status updated','Payment for order '||new.order_number||' is now '||initcap(new.payment_status)||'.');
    end if;
  end if;
  return new;
end; $$;
drop trigger if exists orders_v16_notify_trigger on public.orders;
create trigger orders_v16_notify_trigger after insert or update of status,payment_status on public.orders for each row execute function public.orders_v16_notify();

insert into public.store_settings(key,value) values
('default_delivery_fee','0'),('free_delivery_minimum','0'),('estimated_delivery_days','3')
on conflict (key) do nothing;


-- V17: reporting and invoice foundations
alter table public.orders add column if not exists invoice_number text;
update public.orders set invoice_number='INV-'||replace(order_number,'ORD-','') where invoice_number is null;
create unique index if not exists orders_invoice_number_uidx on public.orders(invoice_number) where invoice_number is not null;

-- Future-proof order numbering: invoice number is generated server-side when an order is created.
create or replace function public.next_invoice_number() returns text language plpgsql security definer set search_path=public as $$
declare n text;
begin
  n:='INV-'||to_char(now(),'YYYYMM')||'-'||lpad((floor(random()*999999)+1)::int::text,6,'0');
  return n;
end; $$;
revoke all on function public.next_invoice_number() from public;
grant execute on function public.next_invoice_number() to authenticated;



-- V18: Payment setup (public-facing instructions only; never store secret merchant/API keys)
insert into public.store_settings(key,value) values
('bank_transfer_enabled','true'),
('bank_account_title',''),
('bank_account_number',''),
('wallet_enabled','true'),
('wallet_number',''),
('wallet_account_name',''),
('payment_instructions','After bank transfer or wallet payment, enter your transaction/reference ID at checkout.'),
('hosted_checkout_url','')
on conflict (key) do nothing;

-- V18 validation helper for storefront payment options. This does not process money.
create or replace function public.get_payment_setup()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into r from public.store_settings
 where key in ('cod_enabled','bank_transfer_enabled','bank_account_title','bank_account_number','wallet_enabled','wallet_number','wallet_account_name','payment_instructions','hosted_checkout_url');
 return r;
end; $$;
revoke all on function public.get_payment_setup() from public;
grant execute on function public.get_payment_setup() to anon, authenticated;

-- ============================================================
-- V19: Payment gateway architecture + security hardening
-- ============================================================
-- Normalize legacy V14/V15 capitalized values before enforcing the V15 lowercase contract.
update public.orders set status=lower(replace(status,' ','_')) where status is not null;
update public.orders set payment_status=lower(payment_status) where payment_status is not null;
update public.orders set status='out_for_delivery' where status='out_for_delivery';

alter table public.orders drop constraint if exists orders_status_check;
alter table public.orders add constraint orders_status_check check (status in ('pending','confirmed','packed','shipped','out_for_delivery','delivered','cancelled'));
alter table public.orders drop constraint if exists orders_payment_status_check;
alter table public.orders add constraint orders_payment_status_check check (payment_status in ('pending','verified','failed','refunded'));

-- Atomic invoice numbering: a BEFORE INSERT trigger assigns the invoice before the order is committed.
create sequence if not exists public.fme_invoice_seq start with 1 increment by 1;
create or replace function public.next_invoice_number() returns text language plpgsql security definer set search_path=public as $$
begin
  return 'INV-'||to_char(now(),'YYYYMM')||'-'||lpad(nextval('public.fme_invoice_seq')::text,6,'0');
end; $$;
revoke all on function public.next_invoice_number() from public;
grant execute on function public.next_invoice_number() to authenticated;

create or replace function public.orders_assign_invoice() returns trigger language plpgsql security definer set search_path=public as $$
begin
  if new.invoice_number is null or btrim(new.invoice_number)='' then new.invoice_number:=public.next_invoice_number(); end if;
  return new;
end; $$;
drop trigger if exists orders_assign_invoice_trigger on public.orders;
create trigger orders_assign_invoice_trigger before insert on public.orders for each row execute function public.orders_assign_invoice();

-- Payment transaction ledger. It records intent/status only; money movement is performed by the gateway/server.
create table if not exists public.payment_transactions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  provider text not null check (provider in ('jazzcash','easypaisa','payfast','manual','other')),
  provider_transaction_id text,
  amount numeric(12,2) not null check (amount>=0),
  currency text not null default 'PKR',
  status text not null default 'pending' check (status in ('pending','authorized','paid','failed','cancelled','refunded')),
  checkout_url text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.payment_transactions enable row level security;
drop policy if exists "payment tx own read" on public.payment_transactions;
create policy "payment tx own read" on public.payment_transactions for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists "payment tx admin all" on public.payment_transactions;
create policy "payment tx admin all" on public.payment_transactions for all using (public.is_admin()) with check (public.is_admin());
create index if not exists payment_transactions_order_idx on public.payment_transactions(order_id,created_at desc);
create index if not exists payment_transactions_provider_idx on public.payment_transactions(provider,provider_transaction_id);

-- Webhook audit log. Only trusted server-side code should write to this table.
create table if not exists public.payment_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  event_type text,
  provider_event_id text,
  signature_valid boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_error text
);
alter table public.payment_webhook_events enable row level security;
drop policy if exists "payment webhook admin read" on public.payment_webhook_events;
create policy "payment webhook admin read" on public.payment_webhook_events for select using (public.is_admin());

-- Server-safe order payment intent creator. It never accepts a secret and never calls a gateway from the browser.
create or replace function public.create_payment_intent(p_order_id uuid,p_provider text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare o public.orders%rowtype; t public.payment_transactions%rowtype; p text;
begin
  if auth.uid() is null then raise exception 'You must be signed in'; end if;
  select * into o from public.orders where id=p_order_id and user_id=auth.uid();
  if not found then raise exception 'Order not found'; end if;
  p:=lower(trim(p_provider));
  if p not in ('jazzcash','easypaisa','payfast') then raise exception 'Unsupported payment provider'; end if;
  if o.payment_status='verified' then raise exception 'Order is already paid'; end if;
  insert into public.payment_transactions(order_id,user_id,provider,amount,currency,status,metadata)
  values(o.id,o.user_id,p,o.total,'PKR','pending',jsonb_build_object('invoice_number',o.invoice_number,'order_number',o.order_number))
  returning * into t;
  return jsonb_build_object('id',t.id,'order_id',t.order_id,'provider',t.provider,'amount',t.amount,'currency',t.currency,'status',t.status);
end; $$;
revoke all on function public.create_payment_intent(uuid,text) from public;
grant execute on function public.create_payment_intent(uuid,text) to authenticated;

insert into public.store_settings(key,value) values
('gateway_provider','none'),('gateway_enabled','false'),('gateway_checkout_url',''),('gateway_merchant_label',''),('gateway_callback_url','')
on conflict (key) do nothing;

-- Keep public payment setup limited to non-secret customer-facing values.
create or replace function public.get_payment_setup()
returns jsonb language plpgsql security definer set search_path=public as $$
declare r jsonb;
begin
 select coalesce(jsonb_object_agg(key,value),'{}'::jsonb) into r from public.store_settings
 where key in ('cod_enabled','bank_transfer_enabled','bank_account_title','bank_account_number','wallet_enabled','wallet_number','wallet_account_name','payment_instructions','hosted_checkout_url','gateway_provider','gateway_enabled','gateway_checkout_url','gateway_merchant_label');
 return r;
end; $$;
revoke all on function public.get_payment_setup() from public;
grant execute on function public.get_payment_setup() to anon, authenticated;

-- V21: WhatsApp Business message audit/outbox. Actual sending must happen in a server-side Edge Function.
create table if not exists public.message_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references auth.users(id) on delete set null,
  order_id uuid references public.orders(id) on delete set null,
  channel text not null check (channel in ('whatsapp','email','sms','other')),
  recipient text,
  template_name text,
  message text,
  provider_message_id text,
  status text not null default 'queued' check (status in ('queued','sent','delivered','read','failed')),
  error_message text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.message_logs enable row level security;
drop policy if exists "message logs own read" on public.message_logs;
create policy "message logs own read" on public.message_logs for select using (user_id=auth.uid() or public.is_admin());
drop policy if exists "message logs admin all" on public.message_logs;
create policy "message logs admin all" on public.message_logs for all using (public.is_admin()) with check (public.is_admin());
create index if not exists message_logs_order_idx on public.message_logs(order_id,created_at desc);
create index if not exists message_logs_status_idx on public.message_logs(status,created_at desc);

-- V22: production hardening for messaging + webhook idempotency + customer tracking.
-- Duplicate provider events must never be processed twice.
create unique index if not exists payment_webhook_events_provider_event_uidx
  on public.payment_webhook_events(provider, provider_event_id)
  where provider_event_id is not null and btrim(provider_event_id) <> '';

-- Queue a customer-facing WhatsApp message whenever a new order or important status changes.
create or replace function public.queue_order_whatsapp_message()
returns trigger language plpgsql security definer set search_path=public as $$
declare msg text; recipient text;
begin
  recipient := nullif(regexp_replace(coalesce(new.phone,''),'[^0-9]','','g'),'');
  if recipient is null then return new; end if;
  if tg_op='INSERT' then
    msg := 'Faheem Mobile and Solar Electronics: Order '||coalesce(new.order_number,'')||' received. Total Rs. '||to_char(coalesce(new.total,0),'FM999,999,990.00')||'. Status: pending.';
  elsif new.status is distinct from old.status then
    msg := 'Faheem Mobile and Solar Electronics: Order '||coalesce(new.order_number,'')||' status updated to '||replace(coalesce(new.status,''),'_',' ')||'. Tracking: '||coalesce(new.tracking_number,'Not assigned')||'.';
  elsif new.payment_status is distinct from old.payment_status then
    msg := 'Faheem Mobile and Solar Electronics: Payment status for order '||coalesce(new.order_number,'')||' is now '||coalesce(new.payment_status,'pending')||'.';
  else return new;
  end if;
  insert into public.message_logs(user_id,order_id,channel,recipient,template_name,message,status)
  values(new.user_id,new.id,'whatsapp',recipient,'order_update',msg,'queued');
  return new;
end; $$;
revoke all on function public.queue_order_whatsapp_message() from public;
drop trigger if exists orders_queue_whatsapp_trigger on public.orders;
create trigger orders_queue_whatsapp_trigger
after insert or update of status,payment_status on public.orders
for each row execute function public.queue_order_whatsapp_message();

-- Secure queue read/update: only admins or the owning customer may read their logs.
-- Sending is intentionally not possible from the browser; the Edge Function consumes queued rows.
create index if not exists message_logs_queue_idx on public.message_logs(channel,status,created_at);


-- V24: WhatsApp queue reliability + operational safety.
-- Adds a processing state, retry metadata, and a server-only claim RPC.
alter table public.message_logs add column if not exists attempt_count integer not null default 0 check (attempt_count >= 0);
alter table public.message_logs add column if not exists claimed_at timestamptz;
alter table public.message_logs add column if not exists next_attempt_at timestamptz;

-- Rebuild the status constraint so the worker can atomically claim a message.
alter table public.message_logs drop constraint if exists message_logs_status_check;
alter table public.message_logs add constraint message_logs_status_check check (status in ('queued','processing','sent','delivered','read','failed'));

create index if not exists message_logs_ready_idx
  on public.message_logs(channel,status,next_attempt_at,created_at);

create or replace function public.claim_whatsapp_message()
returns public.message_logs
language plpgsql
security definer
set search_path=public
as $$
declare r public.message_logs;
begin
  -- Browser users cannot claim/send messages; only trusted server-side callers
  -- should invoke this function with a secret/service role context.
  if auth.role() not in ('service_role') then
    raise exception 'Server-only operation';
  end if;

  select * into r
  from public.message_logs
  where channel='whatsapp'
    and status='queued'
    and (next_attempt_at is null or next_attempt_at <= now())
  order by created_at
  for update skip locked
  limit 1;

  if not found then return null; end if;

  update public.message_logs
  set status='processing', claimed_at=now(), attempt_count=attempt_count+1, updated_at=now()
  where id=r.id
  returning * into r;

  return r;
end;
$$;
revoke all on function public.claim_whatsapp_message() from public;

create or replace function public.finish_whatsapp_message(
  p_id uuid,
  p_success boolean,
  p_provider_message_id text default null,
  p_error text default null
)
returns public.message_logs
language plpgsql
security definer
set search_path=public
as $$
declare r public.message_logs;
  v_attempt integer;
begin
  if auth.role() not in ('service_role') then
    raise exception 'Server-only operation';
  end if;

  select attempt_count into v_attempt from public.message_logs where id=p_id for update;
  if not found then raise exception 'Message not found'; end if;

  update public.message_logs
  set status=case when p_success then 'sent' else case when v_attempt < 5 then 'queued' else 'failed' end end,
      provider_message_id=coalesce(p_provider_message_id,provider_message_id),
      error_message=case when p_success then null else left(coalesce(p_error,'Send failed'),1000) end,
      next_attempt_at=case when p_success or v_attempt >= 5 then null else now() + make_interval(secs => least(3600, power(2, greatest(v_attempt-1,0))*30)::integer) end,
      claimed_at=null,
      updated_at=now()
  where id=p_id
  returning * into r;
  return r;
end;
$$;
revoke all on function public.finish_whatsapp_message(uuid,boolean,text,text) from public;
