import { serve } from 'https://deno.land/std@0.224.0/http/server.ts';
serve(async (req) => {
  if (req.method !== 'GET') return new Response('Method Not Allowed', { status: 405 });
  return Response.json({ ok: true, service: 'faheem-store', version: 'V24', time: new Date().toISOString() });
});
