# Decision log (ADRs)

Lightweight records. One entry per decision: context, decision, status.

## Decisions (PoC defaults)
These were open at the start and are now decided. Each is a default, configurable by the
adopting client (see the "For adopters" tab on the explainer page).
1. **Backend Claude surface**: **Anthropic API direct** for the PoC (simplest, zero Google in
   the path). **Vertex AI** and **Bedrock** are supported as **adapters, not a pure config swap**:
   Vertex moves the model into the URL path, swaps `x-api-key` for a GCP service-account bearer,
   and carries `anthropic_version` in the body; Bedrock needs SigV4 signing (a JS/Java callout)
   and different model IDs. The gateway shape is unchanged, the target leg is re-skinned.
2. **End-user identity model**: support **both** non-Google methods. **Customer-IdP JWT (C)** is
   the lead for enterprise federation, **Apigee API key (A)** for simple apps. Apigee OAuth2 (B)
   stays optional.
3. **Audit depth**: **metadata only** by default (identity, request id, model, token counts,
   status, time), bodies off for privacy and switchable on. Sink: **Apigee Analytics + Cloud
   Logging to BigQuery**, customer SIEM optional.
4. **Cost attribution**: **per principal** (per end user for JWT, per app for API key),
   aggregable to team/tier.
5. **Streaming**: **non-streaming** for v1 so token metering is exact; SSE on the roadmap.
6. **Tenancy**: **single shared proxy** with per-app and per-IdP isolation for the PoC;
   dedicated environment per business unit available for production.

## ADR-0001: Apigee as the single front door
- **Context:** customers want Claude access governed without exposing the Anthropic key or
  requiring Google login.
- **Decision:** all end-user traffic to Claude goes through one Apigee proxy that owns
  auth-verify, quota, spike-arrest, audit, and backend-secret injection.
- **Status:** accepted.

## ADR-0002: Non-Google end-user identity
- **Context:** hard requirement: no Workspace/Cloud-Console login for end-users.
- **Decision:** end-user identity is an Apigee construct (API key / Apigee OAuth2 / customer-IdP
  JWT). Any Google identity exists only as a hidden backend service identity (if Vertex is chosen).
- **Status:** accepted.

## ADR-0003: Backend target
- **Context:** see decision 1. Choice of Claude backend gates the target endpoint and backend auth.
- **Decision:** Anthropic API direct for the PoC. Vertex AI and Bedrock are reachable as adapters
  (different path, auth, and version), not a pure config swap, for clients needing in-cloud
  data residency.
- **Status:** accepted.
