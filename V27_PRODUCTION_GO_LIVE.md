# V27 — Production Go-Live Pack

This release is the final deployment/configuration pack. It does not invent merchant credentials or claim live payment settlement.

## 1. Supabase
1. Create/open the production Supabase project.
2. Apply `supabase_schema.sql`.
3. Set the storefront Supabase URL + publishable key.
4. Link the project with `supabase link --project-ref YOUR_PROJECT_REF`.
5. Deploy all Edge Functions with `supabase functions deploy`.

## 2. Server secrets
Configure secrets in Supabase Edge Function Secrets. Never put secret keys in browser/localStorage or Git.

Expected provider configuration is intentionally adapter-based. Add only credentials supplied by the official provider:
- WHATSAPP_ACCESS_TOKEN
- WHATSAPP_PHONE_NUMBER_ID
- WHATSAPP_VERIFY_TOKEN
- WHATSAPP_APP_SECRET
- PAYMENT_PROVIDER
- PAYMENT_MERCHANT_ID
- PAYMENT_API_KEY / PAYMENT_API_SECRET (only if required by the provider)
- PAYMENT_WEBHOOK_SECRET (only if officially documented)

## 3. Activation gates
Live provider calls remain disabled until all are true:
- merchant account approved
- sandbox credentials tested
- exact provider API/signature documentation confirmed
- webhook signature verification implemented for that provider
- amount + currency + order ID verified before marking payment verified
- idempotency tested
- WhatsApp webhook verification tested
- outbound template/recipient rules approved

## 4. Smoke tests
- customer signup/login
- product search/category
- cart persistence
- stock cannot go below zero
- coupon calculation server-side
- checkout creates one order + invoice
- customer sees only own orders
- admin sees/updates orders
- payment callback with invalid signature is rejected
- duplicate callback is idempotent
- mismatched amount is rejected
- WhatsApp queue creates one message per event
- duplicate worker claim does not send twice
- failed provider call retries only within configured limit

## 5. Rollback
Keep the previous ZIP release. If a provider integration fails, disable its adapter/secrets and keep COD/manual bank-transfer ordering active.
