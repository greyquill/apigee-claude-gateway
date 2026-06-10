#!/usr/bin/env bash
# Exercise the governed call path. The caller holds ONLY an Apigee app key (no Google login).
#
#   GATEWAY_HOST=my-org-eval.apigee.net APP_KEY=xxxxx ./scripts/test-call.sh
#
set -euo pipefail
: "${GATEWAY_HOST:?set GATEWAY_HOST (your Apigee env hostname)}"
: "${APP_KEY:?set APP_KEY (the end-user's Apigee API key)}"
MODEL="${MODEL:-claude-opus-4-8}"

echo "==> Valid call (expect 200 + Claude answer):"
curl -sS -X POST "https://${GATEWAY_HOST}/claude/v1/messages" \
  -H "x-app-key: ${APP_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"max_tokens\":128,\"messages\":[{\"role\":\"user\",\"content\":\"Say hello in one short sentence.\"}]}" \
  | sed 's/.\{0\}//' ; echo

echo "==> No credential (expect 401, backend never hit):"
curl -sS -o /dev/null -w "%{http_code}\n" -X POST "https://${GATEWAY_HOST}/claude/v1/messages" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"max_tokens\":16,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
