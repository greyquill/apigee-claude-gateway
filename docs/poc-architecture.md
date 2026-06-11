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
                                          │  api.anthropic.com    │  (or Vertex AI / Bedrock: see decisions)
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
leg if Claude is reached via Vertex AI: and that is a service identity inside Apigee, invisible
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

1. **VerifyAPIKey** (`VA-VerifyKey`): option A. Rejects unknown/revoked keys, loads the
   Developer App context (app name, developer, custom attrs like `tier`).
   - *or* **ExtractVariables** (`EV-BearerToken`) then **VerifyJWT** (`VJ-VerifyIdpToken`):
     option C. `EV-BearerToken` strips the `Bearer ` prefix into `jwtsrc.token`, then VerifyJWT
     validates the signature against the customer IdP's JWKS and checks `iss`/`aud`/`exp`.
2. **ExtractVariables** (`EV-ReqModel`) reads `model` and `stream` from the body. Then
   **RaiseFault** (`RF-StreamingNotAllowed`) returns 400 when `stream` is true, and **RaiseFault**
   (`RF-ModelNotAllowed`) returns 403 for any model not on the allow-list. Governance controls
   that keep metering exact and cap cost and surface area.
3. **SpikeArrest** (`SA-SmoothBurst`): smooths bursts to protect the backend.
4. **Quota** (`QU-PerAppDaily`): e.g. `1000` calls/day, keyed on the principal, the consumption
   budget that makes "usage" enforceable.
5. **AssignMessage** (`AM-SetTarget`): set target path, content-type, and a correlation id
   (`X-Request-Id`) used in the audit record.
6. **KeyValueMapOperations** (`KVM-GetAnthropicKey`): read the Anthropic API key from an
   **encrypted KVM** (`secrets`), never hard-coded, never returned to the user.
7. **AssignMessage** (`AM-InjectBackendAuth`): set `x-api-key: {private.anthropic.key}` and
   `anthropic-version: 2023-06-01`; **remove** the client `Authorization` header so the
   end-user credential is not forwarded upstream.

Response PostFlow (in order):

7. **ExtractVariables** (`EV-Usage`): pull `usage.input_tokens` / `usage.output_tokens` from
   the Claude response JSON.
8. **AssignMessage** (`AM-Scrub`): strip any backend/debug headers before returning to user.
9. **StatisticsCollector** (`SC-Tokens`): record token counts, principal, auth method, and tier
   into Apigee Analytics custom dimensions. Cost is derived downstream from the token counts.
10. **MessageLogging** (`ML-Audit`): emit a structured audit line (who, app, request id,
    model, tokens, status, timestamp) to syslog/Cloud Logging → **BigQuery/SIEM** sink.

FaultRules:

11. **RaiseFault** mappings: clean 401 (bad/missing credential), 429 (quota or spike),
    502/504 (backend) responses, so failures are governed and legible too.

---

## 4. Secret handling (the crux)
- Anthropic key stored once in an **encrypted KVM** scoped to the environment. Operators rotate
  it in one place. GCP Secret Manager via ServiceCallout is possible but **not equivalent**: it
  adds a network hop of latency per request and a new failure mode, so encrypted KVM is the right
  PoC default and Secret Manager is an opt-in for orgs that mandate it.
- Key injected **only** on the target (backend) leg; **never** logged, **never** echoed,
  **never** present in any response or analytics field.
- End-user credentials and the backend credential are fully decoupled: revoking a user's API
  key does not touch the Anthropic key, and vice-versa.

---

## 5. Streaming (scoped out and enforced)
Claude supports SSE streaming (`stream: true`), but a streamed body has no single `usage` block,
so metering and cost would silently record zero. The PoC scopes to non-streaming, and this is
**enforced, not just declared**: `EV-ReqModel` reads `stream` from the body and
`RF-StreamingNotAllowed` returns a 400 when it is `true`. Streaming with accurate metering (sum
the `message_delta` usage events) is a follow-up.

---

## 6. What the demo shows (acceptance)
1. A call with a valid non-Google credential → 200 + real Claude answer.
2. A call with a missing/invalid credential → 401, no backend hit.
3. A request for a model off the allow-list → 403; a `stream:true` request → 400.
4. Exceeding the quota → 429.
5. The Anthropic key appears **nowhere** in the response or logs visible to the user.
6. An **audit record** in Apigee Analytics (and the BigQuery/SIEM sink) showing principal,
   request id, model, token counts (including cache tokens), status, timestamp for each call.

## 6a. Known limits (honest, for the architect)
- **Usage on errors:** `EV-Usage` only finds a `usage` block on a 2xx body. On 4xx/5xx the token
  fields stay unresolved and `SC-Tokens` records 0, which is why the audit also logs the HTTP
  status so zero-token rows are distinguishable from real ones.
- **Quota counts on policy execution, not backend success:** a request that reaches the backend
  and gets a 502 still consumes quota. Acceptable for the PoC; for production move accounting to
  a post-success step or refund on 5xx.
- **No request-size guard:** SpikeArrest caps rate, not bytes, and LLM payloads are large. A
  content-length check is a worthwhile production add.

---

## 7. Backend decision (decided: Anthropic direct, others as adapters)
Where "Claude" lives changes the target endpoint and the backend auth. These are **adapters, not
a pure config swap**:
- **Anthropic API direct** (`api.anthropic.com`): simplest; backend auth = `x-api-key`, model in
  the body. No Google at all. **This is the PoC default.**
- **Claude on Vertex AI**: model moves into the URL path, backend auth = GCP service-account
  bearer (a Google *service* identity inside Apigee, still invisible to the end-user),
  `anthropic_version` becomes a body field (`vertex-2023-10-16`). Note this breaks the
  body-based `EV-ReqModel` allow-list, which must be re-pointed at the path. Strongest "it runs
  on Google Cloud" story for the Apigee/Google audience.
- **Claude on AWS Bedrock**: SigV4 signing (no native Apigee policy, needs a JS/Java callout or a
  hosted target), different model IDs, the `InvokeModel` path. Cross-cloud story.

**Decision:** PoC on **Anthropic API direct** for speed. The gateway shape (auth, governance,
audit) is unchanged for the other backends; only the target leg is re-skinned.
