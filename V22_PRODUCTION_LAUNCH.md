# V22 Production Launch / Security Hardening

## Included
- Secure customer order-tracking overlay using the authenticated user's own `orders` and `order_timeline` rows.
- Invoice and WhatsApp shortcuts from the tracking view.
- `message_logs` queue entries automatically created for new orders and status/payment changes.
- Unique webhook-event index to prevent the same provider event from being recorded twice.
- Browser never receives or stores WhatsApp/payment provider secrets.

## Edge Function deployment
Supabase's current deployment flow is:

1. `supabase login`
2. `supabase link --project-ref YOUR_PROJECT_REF`
3. `supabase functions deploy create-payment`
4. `supabase functions deploy payment-webhook`
5. Deploy the WhatsApp sender function after adding a provider-specific adapter.

Store secrets only in Supabase Edge Function Secrets. Do not put service/secret keys in `index.html`, localStorage, or `store_settings`.

## WhatsApp sender requirements
Before live sending, configure the official WhatsApp Business/Meta API contract and server-side credentials. The sender should:
- claim queued rows atomically;
- send using the server-side credential;
- write provider message ID and final status back to `message_logs`;
- retry transient failures with a bounded retry count;
- never trust a browser-supplied delivery status.

## Payment webhook requirements
The V20 webhook remains fail-closed. Before enabling live payments:
- implement the selected provider's current signature/HMAC verification;
- verify the provider event ID for idempotency;
- verify order identity and exact amount/currency;
- update payment status only after successful verification;
- record the raw provider event for audit.

## Final live checklist
- [ ] Run the complete `supabase_schema.sql` in the target project.
- [ ] Configure the Project URL + publishable/anon key in the app.
- [ ] Create/promote the admin account.
- [ ] Test customer signup/login.
- [ ] Test product add/edit/delete and stock.
- [ ] Test coupon + secure checkout.
- [ ] Test invoice number generation.
- [ ] Test order tracking/timeline.
- [ ] Test queued WhatsApp messages.
- [ ] Configure and test provider webhook signatures in a sandbox/test environment.
- [ ] Only then enable live payment processing.
