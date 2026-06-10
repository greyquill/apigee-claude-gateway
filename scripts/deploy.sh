#!/usr/bin/env bash
# Deploy the claude-gateway proxy bundle to an Apigee environment.
# Requires: apigeecli (https://github.com/apigee/apigeecli) + gcloud auth.
#
#   APIGEE_ORG=my-org APIGEE_ENV=eval ./scripts/deploy.sh
#
set -euo pipefail

: "${APIGEE_ORG:?set APIGEE_ORG}"
: "${APIGEE_ENV:?set APIGEE_ENV}"
PROXY_NAME="claude-gateway"
BUNDLE_DIR="$(cd "$(dirname "$0")/../proxy/apigee" && pwd)"

TOKEN="$(gcloud auth print-access-token)"

echo "==> Ensuring encrypted KVM 'secrets' exists with the Anthropic key"
echo "    (run once; set ANTHROPIC_API_KEY in your shell, it is NEVER committed)"
if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  apigeecli kvms create --org "$APIGEE_ORG" --env "$APIGEE_ENV" --name secrets --encrypted -t "$TOKEN" || true
  apigeecli kvms entries create --org "$APIGEE_ORG" --env "$APIGEE_ENV" --map secrets \
    --key anthropic_api_key --value "$ANTHROPIC_API_KEY" -t "$TOKEN" || true
else
  echo "    WARNING: ANTHROPIC_API_KEY not set; skipping KVM seed. Set it before the first real call."
fi

echo "==> Importing + deploying proxy '$PROXY_NAME' to $APIGEE_ORG/$APIGEE_ENV"
apigeecli apis create bundle --name "$PROXY_NAME" --proxy-folder "$BUNDLE_DIR/apiproxy" \
  --org "$APIGEE_ORG" --env "$APIGEE_ENV" --ovr --wait -t "$TOKEN"

echo "==> Done. Test with scripts/test-call.sh"
