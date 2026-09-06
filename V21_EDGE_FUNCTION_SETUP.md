
# V21 WhatsApp Business / Messaging Outbox

V21 adds `message_logs` as an audit/outbox table. The browser must not contain a permanent Meta access token or other provider secret.

Recommended flow:
1. Customer/order event creates a queued message through a protected server function.
2. Supabase Edge Function reads the server-side WhatsApp credentials from Function Secrets.
3. Function sends through the official provider API and records provider message ID/status in `message_logs`.
4. Provider webhook updates delivered/read/failed status.
5. Manual `wa.me` remains available as a fallback.

Supabase documents Edge Functions as the server-side location for third-party integrations/webhooks and recommends keeping secrets in Function secrets rather than browser code.
