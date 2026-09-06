# V25 — Live Provider Setup & Fail-Closed Security

## JazzCash
JazzCash provides a merchant payment gateway, secure redirection/Open APIs and sandbox testing. V25 isolates JazzCash verification but intentionally remains fail-closed until the exact merchant account secure-hash field ordering/algorithm is configured from the current official merchant contract and sandbox-tested.

## Easypaisa
Easypaisa provides online payment gateway integration guides and merchant onboarding. V25 isolates Easypaisa verification but intentionally remains fail-closed until the current merchant webhook/signing contract is supplied and sandbox-tested.

## WhatsApp Business
Configure Edge Function secrets: `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_GRAPH_VERSION`, `WHATSAPP_VERIFY_TOKEN`. The `send-whatsapp` function supports webhook verification by GET and queued server-side sending by POST. Never expose the access token in browser code/localStorage.

## Deployment
```bash
export SUPABASE_PROJECT_REF="your-project-ref"
./deploy_functions.sh
```

## Production gate
A browser redirect never marks an order paid. A payment event must pass signature verification, event-id idempotency, order reference, amount/currency matching, and confirmed-success status. Until provider-specific signing is implemented, the function records the event and does not change payment status.
