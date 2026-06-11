# Decision log (ADRs) + open questions

Lightweight records. One entry per decision: context, decision, status.

## Open questions
1. **Backend Claude surface**: Anthropic API direct vs. Claude on Vertex AI vs. Claude on
   AWS Bedrock? Gates target endpoint + backend auth. (Leaning: Anthropic direct for PoC speed,
   designed so Vertex is a config swap.)
2. **End-user identity model**: Apigee API key (A) / Apigee OAuth2 (B) / customer-IdP JWT (C)?
   (Leaning: A first, then C to prove non-Google federation.)
3. **Audit depth**: metadata only, or capture prompt/response bodies too? Where does the sink
   live (BigQuery, customer SIEM)? Any PII/data-residency constraints?
4. **Cost attribution**: per-app, per-end-user, or per-tier? Drives the analytics dimensions.
5. **Streaming**: is SSE required for the demo, or is non-streaming acceptable for v1?
6. **Tenancy**: single shared proxy or per-customer proxy/environment?

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

## ADR-0003: Backend target (PENDING)
- **Context:** see open question 1.
- **Decision:** TBD.
- **Status:** proposed: Anthropic API direct for PoC, Vertex as the swap-in narrative.
