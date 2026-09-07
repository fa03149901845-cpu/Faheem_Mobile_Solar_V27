// V20 payment creation bridge.
// This function is intentionally provider-neutral. Add the chosen provider's
// official API call and signature/auth handling server-side before production.
import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const supabaseUrl = Deno.env.get('SUPABASE_URL')!;
const serviceRole = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!;
const supabase = createClient(supabaseUrl, serviceRole);

serve(async (req) => {
  if (req.method !== 'POST') return new Response('Method Not Allowed', { status: 405 });
  const auth = req.headers.get('authorization');
  if (!auth) return new Response('Unauthorized', { status: 401 });
  const token = auth.replace(/^Bearer\s+/i, '');
  const { data: userData } = await supabase.auth.getUser(token);
  if (!userData.user) return new Response('Unauthorized', { status: 401 });
  const body = await req.json();
  const provider = String(body.provider || '').toLowerCase();
  const orderId = String(body.order_id || '');
  if (!['jazzcash','easypaisa','payfast'].includes(provider) || !orderId) return new Response('Invalid request', { status: 400 });

  // Re-check ownership and authoritative order amount in the database.
  const { data: order, error } = await supabase.from('orders').select('id,order_number,invoice_number,total,payment_status,user_id').eq('id', orderId).eq('user_id', userData.user.id).single();
  if (error || !order) return new Response('Order not found', { status: 404 });
  if (order.payment_status === 'verified') return new Response('Order already paid', { status: 409 });

  // Provider API call belongs here. Secrets must come from Edge Function env vars.
  return new Response(JSON.stringify({ ok: false, provider, order_id: order.id, amount: order.total, message: 'Provider adapter not activated. Configure merchant credentials and official API contract first.' }), { status: 501, headers: { 'content-type': 'application/json' } });
});
