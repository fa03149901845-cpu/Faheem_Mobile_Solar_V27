# V27 Corrected Build

Fixes included:
- Vercel `/api/config` support so public Supabase URL + Publishable/Anon key can be read from Vercel environment variables instead of relying only on browser localStorage.
- Supabase boot now actually runs on page load and then loads online products.
- Online product loading no longer wipes a valid local product cache when the online table is empty.
- Category matching is normalized (solar/solar-panels, inverter/inverters, battery/batteries, etc.).
- Mobile header/action/category navigation is horizontally safe and responsive.

## Vercel environment variables
Use the existing Supabase public values with one supported pair:
- `SUPABASE_URL` + `SUPABASE_PUBLISHABLE_KEY` (preferred), or
- `SUPABASE_URL` + `SUPABASE_ANON_KEY`

Never put a Supabase `service_role`/secret key in these variables or in the browser.

Payment gateway adapters remain fail-closed until real merchant credentials and provider signature verification are configured.


## 2026-09-07 Critical Fix Applied
- Fixed the `printInvoice()` JavaScript parser break in `index.html`.
- Removed the nested `<script>` tag from the invoice HTML template and moved popup printing to a safe `setTimeout()` after `document.close()`.
- Verified all inline JavaScript blocks in `index.html` with Node.js syntax checking; all pass.
