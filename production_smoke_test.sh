#!/usr/bin/env bash
set -euo pipefail
: "${SUPABASE_PROJECT_REF:?Set SUPABASE_PROJECT_REF}"
BASE="https://${SUPABASE_PROJECT_REF}.supabase.co/functions/v1"
printf 'Health endpoint: %s/health-check\n' "$BASE"
printf 'Run authenticated checkout/order tests from the storefront after deployment.\n'
printf 'Do NOT send provider secrets as command-line arguments or commit them to files.\n'
