# Requirements

## Context
Apigee customers need their end-users to consume Claude (Anthropic) services that sit behind
Apigee, **without** logging into anything Google (Workspace or Cloud Console), while Apigee
enforces policy, meters usage, and audits every call. Deliverable: a working proof of concept
that demonstrates the mechanism.

## In scope (PoC)
- One Apigee API proxy that fronts the Claude API.
- End-user authentication using a **non-Google** credential.
- Backend Anthropic credential held in Apigee, injected on the backend leg, hidden from users.
- Governance policies: credential verification, quota, spike arrest, audit logging, usage metering.
- A demonstrable call path + the audit/analytics record proving the call was governed.

## Out of scope (PoC)
- Production multi-tenant hardening, HA, DR.
- Billing/chargeback integration (we capture usage; we do not invoice).
- A customer-facing developer portal (Apigee provides one; not required for the demo).
- Streaming (SSE) metering exactness — noted as a follow-up; PoC uses non-streaming.
- Fine-tuning prompts/guardrails on Claude content (this is a gateway PoC, not an app).

## Functional requirements
- **FR1** End-user calls an Apigee endpoint with a non-Google credential (API key, Apigee OAuth2
  token, or customer-IdP JWT) and receives a valid Claude response.
- **FR2** Requests without a valid credential are rejected at Apigee (401) before reaching Claude.
- **FR3** Apigee injects the Anthropic API key on the backend leg from secure storage (KVM/Secret
  Manager); the key never appears in any user-visible response or log.
- **FR4** Per-app/per-tier **quota** is enforced; exceeding it returns 429.
- **FR5** **Spike arrest** protects the backend from bursts.
- **FR6** Every call produces an **audit record** (identity/app, request id, model, token usage,
  status, timestamp) in Apigee Analytics and an external sink (BigQuery/SIEM).
- **FR7** Token **usage** (input/output) is extracted from the Claude response and metered.
- **FR8** Faults (401/429/5xx) return clean, governed error responses.

## Non-functional requirements
- **NFR1 Security:** no Google login in the end-user path; secrets only in encrypted storage;
  least-privilege backend identity; client credential never forwarded upstream.
- **NFR2 Observability:** every governed decision (allow/deny/quota/cost) is queryable.
- **NFR3 Portability:** backend target (Anthropic direct / Vertex / Bedrock) is a config swap,
  not a rewrite.
- **NFR4 Repeatability:** the proxy bundle deploys from this repo via a script; the demo is
  reproducible from a clean environment.
- **NFR5 Cost control:** PoC stays on free/low-cost tiers; no surprise spend. (Vector hard rule:
  never switch billing models without explicit approval.)

## Prerequisites / accounts
- Apigee org + environment (Apigee X eval is fine for a PoC).
- An Anthropic API key (or Vertex/Bedrock access to Claude, per the backend decision).
- `gcloud` + `apigeecli` (or the Apigee Maven/REST tooling) installed locally for deploy.
- A test non-Google IdP for option C (optional): Okta/Entra/Auth0 dev tenant.

## Success criteria (demo script)
1. Valid non-Google credential → 200 + real Claude answer.
2. Invalid/missing credential → 401, backend never called.
3. Quota exceeded → 429.
4. Anthropic key absent from all user-visible output and logs.
5. Audit + usage record visible in Apigee Analytics and the external sink.
