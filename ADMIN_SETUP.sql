-- FAHEEM MOBILE & SOLAR V27 - ADMIN SETUP
-- Run this in Supabase Dashboard -> SQL Editor.
-- IMPORTANT: replace the email below with the SAME email you use to log in to the website.
-- This does NOT expose or change your Supabase secret key.

update public.profiles
set role = 'admin'
where id = (
  select id from auth.users
  where lower(email) = lower('YOUR_ADMIN_EMAIL')
  limit 1
);

-- Check the result: it should return your admin email and role = admin.
select u.email, p.role, p.full_name
from auth.users u
left join public.profiles p on p.id = u.id
where lower(u.email) = lower('YOUR_ADMIN_EMAIL');

-- If the result says role = admin, return to the website, refresh the page,
-- log out/in if needed, and open Admin Panel again.
