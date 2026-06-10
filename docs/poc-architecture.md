# PoC architecture: Apigee → Claude governance gateway (one page)

**Goal:** an end-user holding a non-Google credential calls an Apigee endpoint and receives a
Claude response. The Anthropic credential never leaves Apigee. Every call is policed and audited.

---

## 1. Proxy flow (request lifecycle)

```
 ┌──────────┐   1. POST /v1/messages            ┌─────────────────────────────────────────┐
 │ End-user │   Authorization: Bearer <token>   │            Apigee API proxy              │
 │  (app)   │ ────────────────────────────────► │  ProxyEndpoint  →  TargetEndpoint        │
 └──────────┘   (NO Google login anywhere)      └─────────────────────────────────────────┘
                                                   │ PreFlow (request)
                                                   │  a. VerifyAPIKey  OR  VerifyJWT        ← non-Google identity
                                                   │  b. SpikeArrest                        ← smooth burst
                                                   │  c. Quota                              ← per-app/tier budget
                                                   │  d. (opt) OAuthV2 token validate
                                                   │  e. AssignMessage: set backend headers
                                                   │  f. KeyValueMapOperations: read secret ← Anthropic key from KVM
                                                   │  g. AssignMessage: inject x-api-key,   ← key hidden from user
                                                   │       anthropic-version; strip client Authorization
                                                   │  h. ServiceCallout/Log: write audit    ← "everything is tracked"
                                                   ▼
                                          ┌──────────────────────┐
                                          │   Claude backend      │  Anthropic API direct
                                          │  api.anthropic.com    │  (or Vertex AI / Bedrock — see decisions)
                                          └──────────────────────┘
                                                   │ PostFlow (response)
                                                   │  i. ExtractVariables: usage.input/output tokens
                                                   │  j. AssignMessage: strip backend/debug headers
                                                   │  k. StatisticsCollector: meter tokens + cost
                                                   │  l. MessageLogging: ship audit to SIEM/BigQuery
                                                   ▼
 ┌──────────┐   200 OK + Claude response        (Apigee Analytics records the governed call)
 │ End-user │ ◄───────────────────────────────────────────────────────────────────────────────
 └──────────┘
```

**Why no Google login:** end-user identity is established by an Apigee construct (API key,
Apigee-minted OAuth2 token, or a JWT from the customer's own IdP). None of these touch Google
Workspace or the Cloud Console. The only place a Google identity could appear is the *backend*
leg if Claude is reached via Vertex AI — and that is a service identity inside Apigee, invisible
to the end-user.

---

## 2. Identity model (pick one for the PoC; A is simplest)

| Option | End-user holds | Apigee verifies with | Notes |
|---|---|---|---|
| **A. Apigee API key** | API key tied to an Apigee Developer App | `VerifyAPIKey` | Simplest demo. Maps cleanly to per-app quota + analytics. |
| **B. Apigee OAuth2 (client credentials)** | short-lived bearer token from Apigee's token endpoint | `OAuthV2 (VerifyAccessToken)` | Token rotation, scopes. Apigee is the Authorization Server. |
| **C. Customer-IdP JWT** | JWT from customer's Okta/Entra/Auth0 | `VerifyJWT` (JWKS) | Federates to customer identity, still zero Google. Best "real" story. |

**PoC recommendation:** build **A** end-to-end first (fastest path to a working demo), then add
**C** to prove federation to a non-Google IdP. B is optional.

**Wired in the bundle (A + C):** the proxy does conditional auth in the PreFlow. If the caller
sends an `Authorization: Bearer` token it is verified as a customer-IdP JWT (`VJ-VerifyIdpToken`,
configured by `resources/properties/idp.properties`); otherwise an Apigee API key in `x-app-key`
is verified (`VA-VerifyKey`). Both paths then resolve a single `gw.principal` (JWT `sub` or API-key
`client_id`) via `AM-PrincipalFromJwt` / `AM-PrincipalFromKey`, so quota, usage metering, and audit
are identical regardless of auth method. Neither end-user credential is forwarded upstream.

---

## 3. The specific Apigee policies

Request PreFlow (in order):

1. **VerifyAPIKey** (`VA-VerifyKey`) — option A. Rejects unknown/revoked keys; loads the
   Developer App context (app name, developer, custom attrs like `tier`).
   - *or* **VerifyJWT** (`VJ-VerifyIdpToken`) — option C, validates signature against the
     customer IdP's JWKS, checks `iss`/`aud`/`exp`.
2. **SpikeArrest** (`SA-SmoothBurst`) — e.g. `30pm` per processor, protects the backend from bursts.
3. **Quota** (`QU-PerAppDaily`) — e.g. `1000` calls/day, keyed on the app/tier; the consumption
   budget that makes "usage" enforceable.
4. **AssignMessage** (`AM-SetTarget`) — set target path, content-type, and a correlation id
   (`X-Request-Id`) used in the audit record.
5. **KeyValueMapOperations** (`KVM-GetAnthropicKey`) — read the Anthropic API key from an
   **encrypted KVM** (`secrets`), never hard-coded, never returned to the user.
6. **AssignMessage** (`AM-InjectBackendAuth`) — set `x-api-key: {private.anthropic.key}` and
   `anthropic-version: 2023-06-01`; **remove** the client `Authorization` header so the
   end-user credential is not forwarded upstream.

Response PostFlow (in order):

7. **ExtractVariables** (`EV-Usage`) — pull `usage.input_tokens` / `usage.output_tokens` from
   the Claude response JSON.
8. **AssignMessage** (`AM-Scrub`) — strip any backend/debug headers before returning to user.
9. **StatisticsCollector** (`SC-Tokens`) — record tokens (and a computed cost) into Apigee
   Analytics custom dimensions, per app/developer.
10. **MessageLogging** (`ML-Audit`) — emit a structured audit line (who, app, request id,
    model, tokens, status, timestamp) to syslog/Cloud Logging → **BigQuery/SIEM** sink.

FaultRules:

11. **RaiseFault** mappings — clean 401 (bad/missing credential), 429 (quota or spike),
    502/504 (backend) responses, so failures are governed and legible too.

---

## 4. Secret handling (the crux)
- Anthropic key stored once in an **encrypted KVM** scoped to the environment, or in
  GCP Secret Manager fetched via ServiceCallout. Operators rotate it in one place.
- Key injected **only** on the target (backend) leg; **never** logged, **never** echoed,
  **never** present in any response or analytics field.
- End-user credentials and the backend credential are fully decoupled: revoking a user's API
  key does not touch the Anthropic key, and vice-versa.

---

## 5. Streaming note
Claude supports SSE streaming (`stream: true`). Apigee can proxy SSE, but token-counting and
some response policies behave differently on a streamed body. **PoC scope:** start with
non-streaming (`stream: false`) so usage metering is exact; note streaming as a follow-up.

---

## 6. What the demo shows (acceptance)
1. A call with a valid non-Google credential → 200 + real Claude answer.
2. A call with a missing/invalid credential → 401, no backend hit.
3. Exceeding the quota → 429.
4. The Anthropic key appears **nowhere** in the response or logs visible to the user.
5. An **audit record** in Apigee Analytics (and the BigQuery/SIEM sink) showing app, request id,
   model, token counts, status, timestamp for each call.

---

## 7. Backend decision gate (resolve at 4pm)
Where does "Claude" live? It changes the target endpoint and the backend auth:
- **Anthropic API direct** (`api.anthropic.com`) — simplest; backend auth = `x-api-key`. No Google at all.
- **Claude on Vertex AI** — backend auth = GCP service-account token (a Google identity, but a
  *service* identity inside Apigee, still invisible to the end-user). Strongest "it's on Google
  Cloud" story for the Apigee/Google audience.
- **Claude on AWS Bedrock** — backend auth = SigV4. Cross-cloud story.

**Recommendation:** PoC on **Anthropic API direct** for speed, and design the target endpoint so
swapping to **Vertex** is a config change (it is the most compelling narrative for a Google audience).
