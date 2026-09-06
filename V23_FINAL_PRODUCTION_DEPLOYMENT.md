# V23 Final Production Deployment Kit

This release prepares the Faheem Mobile and Solar Electronics store for a controlled production launch.

## 1. Supabase project

Run the complete `supabase_schema.sql` in the target Supabase project. Then configure the storefront with the project's URL and public/publishable key.

Never put a secret/service key, payment merchant secret, WhatsApp access token, or webhook signing secret in `index.html`, browser storage, or `store_settings`.

## 2. Deploy Edge Functions

From the project root:

```bash
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase functions deploy create-payment
supabase functions deploy payment-webhook
```

Supabase supports deploying individual or all Edge Functions through the CLI. Production secrets should be stored as Edge Function secrets. See the official documentation:
- https://supabase.com/docs/guides/functions/deploy
- https://supabase.com/docs/guides/functions/secrets

## 3. Production secrets

Set only the secrets required by the provider adapter, for example:

```bash
supabase secrets set PAYMENT_PROVIDER=...
supabase secrets set PAYMENT_MERCHANT_ID=...
supabase secrets set PAYMENT_MERCHANT_SECRET=...
supabase secrets set PAYMENT_WEBHOOK_SECRET=...
supabase secrets set WHATSAPP_ACCESS_TOKEN=...
supabase secrets set WHATSAPP_PHONE_NUMBER_ID=...
```

Use the exact names expected by your final adapter. Do not copy these example values literally.

## 4. Payment gateway go-live gate

A provider adapter is not considered live until all of these pass in sandbox/test mode:

- authenticated order ownership check
- authoritative amount and currency check
- provider request created server-side
- provider callback signature/HMAC verified
- provider event ID is idempotent
- duplicate callbacks do not double-update an order
- successful payment changes `payment_status` only after verification
- failed/expired/refunded events are handled explicitly
- transaction ID is stored in `payment_transactions`
- raw callback is retained in `payment_webhook_events`

The current bridge intentionally does not pretend that payment money movement is active without the provider-specific adapter.

## 5. WhatsApp Business go-live gate

For official WhatsApp Business API automation, configure the Meta/WhatsApp Business Platform webhook and server-side credentials. The outbound worker must atomically claim queued messages, send them using the secret token, and write the provider message ID/status back to `message_logs`.

Required protections:

- bounded retries for transient errors
- no retry storm
- idempotent provider message/event handling
- no browser-controlled delivery status
- log errors without logging access tokens

Meta's WhatsApp Business Platform webhook documentation describes HTTPS callbacks for subscribed events:
https://www.postman.com/meta/whatsapp-business-platform/folder/lboq68h/webhooks

## 6. Final browser test

Customer:
1. Sign up/login.
2. Browse/search/filter products.
3. Add products to cart.
4. Confirm stock limits.
5. Apply a coupon.
6. Checkout.
7. Confirm order number + invoice number.
8. Open My Orders / Track Order.
9. Verify timeline, courier, ETA and invoice.
10. Verify WhatsApp fallback link.

Admin:
1. Login as admin.
2. Add/edit product and stock.
3. Manage category/coupon.
4. Review customer.
5. Review order.
6. Update order/payment/tracking status.
7. Confirm timeline and customer notification.
8. Open professional invoice.
9. Run reports and export CSV.
10. Review payment/message/webhook audit records.

## 7. Launch rule

Do not enable real payment settlement or automated WhatsApp sending merely because the UI is present. Enable each provider only after its official merchant onboarding, credentials, current API contract, callback verification and sandbox tests have passed.
