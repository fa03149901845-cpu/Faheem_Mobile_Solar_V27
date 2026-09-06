# V24 Production Hardening

## What changed
- Added `health-check` Edge Function for a simple production smoke test.
- Added `send-whatsapp` server-side worker.
- Added atomic WhatsApp queue claiming with `FOR UPDATE SKIP LOCKED`.
- Added bounded exponential retry metadata (maximum 5 attempts).
- Added `processing` state to `message_logs`.
- Browser cannot claim or send queued messages.
- WhatsApp access token and phone-number ID are read only from Edge Function secrets.

## Deploy
```bash
export SUPABASE_PROJECT_REF=YOUR_PROJECT_REF
./deploy_functions.sh
```

Supabase's current production flow supports linking a project and deploying Edge Functions with the CLI. Secrets should be configured as Edge Function secrets, not in browser code. See the official Supabase docs:
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/secrets

## WhatsApp configuration
Configure these production secrets only after completing the merchant's official WhatsApp Business Platform setup:

```bash
supabase secrets set WHATSAPP_ACCESS_TOKEN=...
supabase secrets set WHATSAPP_PHONE_NUMBER_ID=...
supabase secrets set WHATSAPP_GRAPH_VERSION=...
```

Do not put these values in `index.html`, `localStorage`, or `store_settings`.

## Important
The worker sends plain text messages. For business-initiated notifications that require approved message templates under the merchant's WhatsApp setup, add the approved template payload and template name in the worker before enabling automatic production messaging.

## Payment
V24 does not claim that JazzCash/Easypaisa/PayFast money movement is live. Payment provider adapters still require the merchant's official credentials, current API contract, callback verification, amount matching and sandbox testing before settlement is enabled.
