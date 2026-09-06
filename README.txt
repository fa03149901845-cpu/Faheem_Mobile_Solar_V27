Faheem Mobile and Solar Electronics - V12

V12 adds Admin Categories management, coupon/discount management + validation, and customer Address Book.

Setup:
1. Create/configure Supabase.
2. Run supabase_schema.sql in Supabase SQL Editor (safe migration for V5-V11).
3. Configure Project URL + public anon/publishable key using the in-app Backend button.
4. Create a customer account and promote the account to admin using the SQL shown in the schema.
5. Product image uploads require the product-images storage bucket/policies from the schema.

Security:
- Never use or expose a Supabase service_role key in the browser.
- Products, orders, categories, coupons and addresses use RLS.
- Order creation continues to use the secure server-side RPC with authoritative DB prices and stock checks.
- Coupon validation is available for admin-created codes; the current checkout does not yet apply coupon discounts to the secure order total.

V13 SECURE COUPONS
- Checkout coupon discount is now calculated and applied inside create_order_secure on the server.
- Coupon usage is incremented atomically only after the order is created.
- Orders store coupon_code and discount.
- Customer profile update RLS policy is included.
- Re-run the complete supabase_schema.sql in Supabase SQL Editor, then test a signed-in customer checkout with a coupon.


V14 additions
- Admin Customers: secure customer summary with email, profile, order count and non-cancelled spend.
- Advanced Admin Orders: search/filter by order/customer/phone, order item details, order status, payment status, and tracking/consignment number.
- Payment tracking fields: payment_status = Pending / Verified / Failed / Refunded.
- Order tracking field: tracking_number.
- Store Settings: store name, WhatsApp, phone, email, city/address, currency and COD toggle.
- V14 SQL removes the legacy 8-argument create_order_secure RPC; the coupon-aware 9-argument version is the only order-creation RPC.
- No real payment gateway is claimed or included yet. Gateway integration can be added later without trusting browser totals.

V15 additions
- Delivery fields: shipping provider, tracking number, estimated delivery, delivered timestamp.
- Order timeline table with customer-owned read access and admin management.
- Secure admin_update_order_tracking RPC for status/payment/delivery/timeline updates.
- Customer My Orders now displays delivery tracking and timeline.
- Admin Orders adds courier, ETA, timeline note and WhatsApp notification action.
- Payment statuses remain preparation/tracking only; no payment gateway is falsely claimed as integrated.

V16 - Customer Experience + Notifications + Invoice
- In-app customer notifications with read/unread state.
- Automatic notifications for new orders, order status and payment status changes.
- Customer invoice print view and WhatsApp tracking shortcut.
- Payment Reference / Transaction ID stored securely with orders.
- Server-side payment-method validation and COD setting enforcement.
- Store delivery defaults: delivery fee, free-delivery minimum and estimated delivery days.
- Order timeline and notification triggers are server-side; customer cannot forge user_id.
- No real payment gateway, SMS, email or push provider is claimed as integrated in V16.

V18 - Payment Setup + Professional Invoices
- Added admin Payment Setup for bank transfer and EasyPaisa/JazzCash customer-facing instructions.
- Added optional public hosted checkout URL field (URL only; no secret keys stored).
- Added get_payment_setup() RPC for safe payment configuration retrieval.
- Added professional printable invoice/receipt renderer with invoice number, customer, payment reference, line items, discount and total.
- Fixed invoice buttons so both Admin and Customer invoice actions work.
- IMPORTANT: V18 does not claim a real payment gateway is integrated. Actual merchant API credentials and server-side webhook integration must be added for a chosen provider.
- Never put service_role or secret merchant/API keys in browser code or store_settings.


V19 PAYMENT GATEWAY + SECURITY HARDENING
- Added payment_transactions ledger and payment_webhook_events audit table.
- Added secure create_payment_intent(order, provider) RPC for JazzCash/Easypaisa/PayFast intent creation. It does not process money or expose secrets.
- Added Admin Payment Gateway setup for provider selection, public hosted checkout/server endpoint and callback URL.
- Added atomic invoice-number trigger so new orders receive an invoice number before commit.
- Normalized legacy order/payment status values to lowercase and re-enforced consistent constraints.
- Live gateway processing must be implemented in a Supabase Edge Function/server using merchant credentials and provider-specific signature verification. Never put secret keys, passwords, access codes or tokens in index.html.
- Current official provider research: JazzCash documents payment gateway, secure redirection and Open APIs; Easypaisa provides online payment gateway integration guides. Merchant onboarding is required before live processing.
- Manual bank/wallet/WhatsApp checkout remains available as fallback.


V20 - SECURE PAYMENT BRIDGE
- Added Supabase Edge Function templates under supabase/functions/create-payment and supabase/functions/payment-webhook.
- create-payment verifies the authenticated user owns the order and reads the authoritative amount before a provider API call.
- payment-webhook records callbacks in payment_webhook_events and is fail-closed until provider-specific signature verification is implemented.
- Added V20_EDGE_FUNCTION_SETUP.md with deployment, secret handling, idempotency and verification rules.
- No real money movement is claimed in this release. Live JazzCash/Easypaisa processing requires merchant onboarding and the provider's current API/signature contract.
- Never place SUPABASE_SERVICE_ROLE_KEY, merchant passwords, access codes, hashes or API tokens in index.html/localStorage/store_settings.

V21 additions:
- Advanced Sales Report CSV export.
- Report rows retain invoice number/customer/payment status.
- message_logs outbox/audit table for server-side WhatsApp Business/email/SMS automation.
- Messaging secrets are never stored in browser/localStorage.
- Supabase Edge Functions are the intended secure bridge for provider API calls and webhooks.

V22 - PRODUCTION LAUNCH / SECURITY HARDENING
- Added authenticated customer Track Order view with timeline, courier, ETA, tracking, invoice and WhatsApp actions.
- Added server-side message queue trigger for new orders and status/payment changes.
- Added unique webhook event index for provider-event idempotency.
- Added V22_PRODUCTION_LAUNCH.md deployment and final security checklist.
- Live WhatsApp sending and live payment processing still require provider-specific server-side adapters, credentials and official signature verification.

V23 - FINAL PRODUCTION DEPLOYMENT KIT
- Added V23_FINAL_PRODUCTION_DEPLOYMENT.md with controlled launch gates for Supabase, payment webhooks and WhatsApp automation.
- Added deploy_functions.sh for repeatable deployment of the current payment bridge functions.
- Production secrets remain server-side only.
- Payment settlement and automated WhatsApp sending remain disabled until official provider adapters, credentials, signature verification and sandbox tests are completed.


V24: Production hardening adds health-check and a server-side WhatsApp worker with atomic queue claiming and bounded retries. Payment gateways remain disabled until provider-specific adapters and official callback verification are configured.

V25: provider-specific payment verification boundaries for JazzCash/Easypaisa are fail-closed; WhatsApp worker supports Meta webhook verification and server-side queued sending. Live payment settlement still requires official merchant signing configuration and sandbox verification.

V27 PRODUCTION GO-LIVE PACK
- Added supabase/config.toml with explicit function JWT settings.
- Added V27_PRODUCTION_GO_LIVE.md with deployment, secret, activation-gate, smoke-test and rollback procedures.
- Added production_smoke_test.sh.
- Provider credentials and live settlement remain disabled until official merchant credentials and provider-specific verification are configured.
