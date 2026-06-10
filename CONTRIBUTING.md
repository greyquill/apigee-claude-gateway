# Working in this repo

## Conventions
- Apigee policy files are named `<Type-Abbrev>-<Purpose>.xml` (e.g. `VA-VerifyKey`, `QU-PerAppDaily`).
  The policy `name` attribute must match the filename (minus `.xml`) and the `<Step>` references.
- Docs are the contract. If you change a policy, update `docs/poc-architecture.md` to match.
- Record any non-trivial choice in `docs/decisions.md` as a short ADR.

## Hard rules (non-negotiable for this PoC)
- **No secrets in git.** The Anthropic key, app keys, JWTs, and tokens live only in the Apigee
  KVM / your shell env. `.gitignore` blocks `.env` and `*.key`; keep it that way.
- **No Google login in the end-user path.** Any Google identity may exist only as a hidden
  backend service identity (if the Vertex target is chosen). If a change forces an end-user to
  authenticate with Google, it is wrong by definition.
- **The Anthropic key is injected on the backend leg only** and never appears in a user-visible
  response, header, or log.
- **No surprise spend.** Stay on Apigee eval + low token caps for the PoC.

## Local flow
1. Edit the bundle under `proxy/apigee/apiproxy/`.
2. `APIGEE_ORG=… APIGEE_ENV=… ANTHROPIC_API_KEY=… ./scripts/deploy.sh`
3. `GATEWAY_HOST=… APP_KEY=… ./scripts/test-call.sh`
4. Check Apigee Analytics + the audit log for the governed record.

## Layout
```
docs/        architecture, requirements, decisions
proxy/apigee/apiproxy/   the deployable Apigee bundle (manifest, proxy, target, policies)
scripts/     deploy + test helpers
```
