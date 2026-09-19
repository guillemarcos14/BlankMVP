# BM phased hardening plan

## Phase 1 — stability before consolidation

Status: implemented in `c487283`.

- One shared builder defines the executable action envelope for WhatsApp, SMS and the native inbox.
- Onboarding preserves any active non-onboarding action instead of overwriting it.
- WhatsApp onboarding is marked `dispatched` only after every required provider request is accepted.
- Partial onboarding delivery is resumable and does not resend steps already accepted.
- English-only copy, Blankmind naming, notification wording and the independent quality judge use the notification-tap contract.
- No database migration, public endpoint change, deployment or iOS execution change is included.

## Objective trigger for phase 2

Phase 2 starts only when all of these facts are recorded for the same release candidate:

1. Phase 1 is integrated and deployed through the protected Backend Cloud release flow, with production Function digests matching the candidate.
2. Product harness remains `33/33` and the required release-gate groups remain `18/18` for that candidate.
3. The matching iOS checkout compiles with `BUILD SUCCEEDED`.
4. A physical iPhone test records: connection onboarding, notification tap opening the picker, selection ending in `verified`, cancellation ending in `dismissed`, and a later protection request ending in device-backed `verified`.
5. There is no open P0/P1 regression in onboarding, action persistence, notification delivery or native acknowledgement.

A daily thread heartbeat checks these facts. It stays silent while any criterion is missing. When all are present, it starts phase 2 automatically and reports the evidence used.

## Phase 2 — internal consolidation

- Move enqueue, conflict policy, delivery progress and lifecycle transitions into one assistant-action service.
- Keep `whatsapp-agent`, `sms-agent` and `assistant-channel` endpoints stable as adapters.
- Preserve current persisted fields and accept legacy action envelopes; add fields only when backward-compatible.
- Route legacy SMS commands through the same service without removing them until production evidence shows they are unused.
- Add parity, supersession, retry and concurrency tests before replacing the remaining duplicated queue code.
- Prepare and push an integration candidate, but do not deploy automatically.

## Backend Cloud handoff

```text
Objetivo: estabilizar onboarding y acciones pendientes antes de la consolidación interna de fase 2.
Rama: codex/backend-release-bm-single-block-2026-09-17
Commit: c487283

Archivos/superficies modificadas:
- Netlify BM onboarding, WhatsApp, SMS, action inbox and APNs copy.
- Shared pending-action builder and regression tests.
- Independent quality judge and synthetic naming expectations.

Migraciones Supabase:
- Ninguna.

Variables de entorno:
- Ninguna nueva.

Validaciones ejecutadas:
- Product harness with baseline and --enforce-scope: 33/33.
- BM release gate --quick: 18/18 required groups.
- WhatsApp, SMS/audio, onboarding hardening, action envelope, autonomous messaging and evaluator integrity tests: pass.
- git diff --check: pass.

Pruebas pendientes:
- Protected Backend Cloud integration/deploy and exact runtime digest verification.
- Physical iPhone notification/picker/verified/dismissed flow.

Riesgos o conflictos conocidos:
- Legacy compatibility evaluation remains diagnostic and still reflects obsolete language/behavior expectations; it is not a required release group.
```
