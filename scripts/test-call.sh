#!/usr/bin/env bash
# Exercise the governed call path. End-users hold ONLY a non-Google credential.
#
#   Option A (Apigee API key):
#     GATEWAY_HOST=my-org-eval.apigee.net APP_KEY=xxxxx ./scripts/test-call.sh
#
#   Option C (customer-IdP JWT): also pass a Bearer token:
#     GATEWAY_HOST=... APP_KEY=xxxxx IDP_JWT=eyJ... ./scripts/test-call.sh
#
set -euo pipefail
: "${GATEWAY_HOST:?set GATEWAY_HOST (your Apigee env hostname)}"
MODEL="${MODEL:-claude-opus-4-8}"
BODY="{\"model\":\"${MODEL}\",\"max_tokens\":128,\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}]}"

if [[ -n "${APP_KEY:-}" ]]; then
  echo "==> Option A: valid API key (expect 200 + Claude answer):"
  curl -sS -X POST "https://${GATEWAY_HOST}/claude/v1/messages" \
    -H "x-app-key: ${APP_KEY}" -H "Content-Type: application/json" -d "$BODY"; echo
fi

if [[ -n "${IDP_JWT:-}" ]]; then
  echo "==> Option C: valid customer-IdP JWT (expect 200 + Claude answer):"
  curl -sS -X POST "https://${GATEWAY_HOST}/claude/v1/messages" \
    -H "Authorization: Bearer ${IDP_JWT}" -H "Content-Type: application/json" -d "$BODY"; echo
fi

echo "==> No credential (expect 401, backend never hit):"
curl -sS -o /dev/null -w "HTTP %{http_code}\n" -X POST "https://${GATEWAY_HOST}/claude/v1/messages" \
  -H "Content-Type: application/json" -d "$BODY"
