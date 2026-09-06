# V20 Edge Function Setup

This release prepares the store for real server-side payment processing without putting merchant secrets in `index.html`.

## Functions
- `payment-webhook`: receives provider callbacks, records an audit event, and is deliberately fail-closed until provider signature verification is implemented.
- `create-payment`: verifies the signed-in customer owns the order and reads the authoritative order amount. It returns 501 until the selected provider adapter is configured.

## Production rule
Do not set `orders.payment_status = verified` from the browser. A provider callback must be cryptographically verified, match the order and exact amount/currency, be idempotent, then update the payment transaction and order server-side.

## Environment secrets
Set only in Supabase Edge Function secrets:
- `SUPABASE_URL`
- `SUPABASE_SERVICE_ROLE_KEY`
- Provider-specific merchant credentials after onboarding

Never paste these into `index.html`, localStorage, store_settings, or Git.

## Provider onboarding
JazzCash documents merchant gateway, secure redirection and Open APIs; Easypaisa provides an online payment gateway and integration guides. Live use requires merchant onboarding and the provider's current credentials/API contract.
