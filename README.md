# Apigee → Claude governance gateway (PoC)

A proof of concept showing how **Apigee** can front **Claude (Anthropic)** services so that
end-users consume Claude through Apigee **without logging into anything Google** (Google
Workspace or the Google Cloud Console), while Apigee remains the governance layer:
policy enforcement, usage metering, and full audit. Everything is tracked.

> Source: a problem handed to Amar by a contact at Google. Goal: a clean, demonstrable PoC
> that proves the mechanism. Brainstorm meeting 2026-06-10 16:00 IST.

## The one-line problem
End-users hold a **non-Google credential**, call an **Apigee endpoint**, and get a **Claude**
response. The real Anthropic key never leaves Apigee. Apigee enforces policy and writes an
audit record for every call.

## What this repo holds
| Path | What |
|---|---|
| `docs/index.html` | **Visual explainer** (tabbed: Architecture incl. cloud diagram, Requirements, Status &amp; Deployment, Open questions). Hosted on GitHub Pages: see below. |
| `docs/poc-architecture.md` | **The one-page PoC architecture** (proxy flow + the specific Apigee policies). Start here. |
| `docs/requirements.md` | Functional + non-functional requirements, scope, and success criteria. |
| `docs/decisions.md` | Decision log (ADRs) and the open questions. |
| `proxy/apigee/` | Apigee proxy bundle: policies + proxy/target endpoint config (the deployable artifact). |
| `scripts/` | Helper scripts to deploy the bundle and exercise the call path. |
| `CONTRIBUTING.md` | How to work in this repo (conventions, the hard rules). |

## Live explainer
Hosted on GitHub Pages (both URLs serve the same page):
- **https://www.greyquill.io/apigee-claude-gateway/** (custom domain)
- https://greyquill.github.io/apigee-claude-gateway/

## Quick mental model
```
end-user (non-Google token)
        │
        ▼
   Apigee proxy  ──[ verify creds · quota · spike arrest · audit log ]──┐
        │                                                               │
        │  inject Anthropic key from KVM (hidden from user)             ▼
        ▼                                                          Apigee Analytics
   Claude API (Anthropic / Vertex / Bedrock)                       + SIEM/BigQuery sink
        │
        ▼
   response  ──[ strip backend headers · meter tokens ]──►  end-user
```

## Status
Seed. The backend Claude surface (Anthropic API direct vs. Vertex AI vs. Bedrock) is the
key open decision and gates the design. See `docs/decisions.md`.
