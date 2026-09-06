#!/usr/bin/env bash
set -euo pipefail
: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF}"
supabase link --project-ref "$SUPABASE_PROJECT_REF"
supabase functions deploy health-check
supabase functions deploy create-payment
supabase functions deploy payment-webhook
supabase functions deploy send-whatsapp
