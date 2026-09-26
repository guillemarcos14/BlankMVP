# BM product journeys v1 — development corpus

Authored 2026-09-26 from the current canonical distraction selection and native action contracts. Generator: `tools/build_bm_product_journeys.js`. Dataset: `tools/datasets/bm_product_journeys_v1.json`; reproducible counts and byte SHA-256 are in its adjacent `.manifest.json`.

## What is measured

The corpus contains **40 explicitly authored base journeys crossed with five stateful continuations: 200 combinations, 925 turns**. It is not 200 independent base scenarios, a heldout, or a collection of user transcripts. Every continuation inherits the base's conversation and real simulated native context. No ID, channel, language, app name, or numeric substitution multiplies the count.

There are 160 distinct input sequences, 200 distinct expected/context sequences, 249 distinct input/gold pairs, and 160 turns asserting correction history. The 40 identical-input pairs deliberately contrast revoked permission with removed native selection: the same user instruction requires different setup actions. These are distinct state-dependent behaviors, not additional linguistic diversity.

The bases cover missing facts and out-of-order answers, immediate duration bounds, exact intervals and overnight arithmetic, recurrence and expiry, inconsistent facts, unsupported strict schedules/limits, rejected facts, corrections, advice-to-action consent, cancellation, unavailable capabilities, retrospective context, privacy questions, and native presence/permission/selection recovery. Each crosses withdrawal, authorized duration amendment, capability change, permission loss, and selection loss. The complete base purposes are in the manifest.

The generator imports only filesystem, path, and crypto utilities. Expected facts, missing fields, decisions, and actions are authored explicitly; interval arithmetic is mathematical normalization. It never imports or samples the tested parser, reducer, model, renderer, oracle, or judge. Oracle schema validation requires complete expected state and actions. Current presence fixtures use `__REPLAY_NOW__` and explicit readiness state; historical heldout datasets remain unchanged.

## Contract and audit decisions

- A complete explicit activation instruction authorizes the canonical distraction selection without redundant confirmation. A later acknowledgement cannot enqueue it again. Native success is never inferred from a planner action.
- Correction changes only the supplied or rejected fact and its derived dependencies. Permission and selection come from per-turn native context; saying “Ready” without changed context cannot manufacture them.
- A daily limit action carries minutes, not an expiry or scheduled start. A requested seven-day limit must remain unresolved until the user explicitly accepts removing the expiry or changes the request. Merely changing the start or saying yes cannot silently discard it.
- In advice, the action-type prompt explicitly proposes converting the discussed facts into a blocking proposal. The subsequent yes accepts that concrete proposal; it does not choose between unoffered alternatives. Independent visible review must still check that prompt.
- The corpus is English and uses the WhatsApp planner context for shared intelligence. It establishes neither Spanish parity nor SMS/provider delivery, authentication, concurrency, physical enforcement, or iPhone receipts.

Independent review inspected all 40 definitions and five continuations. A structural audit removing nominal numeric, time, channel, and language variation distinguished all 40 bases. Review found a real authoring error in `limit_scheduled_rejected`: the first draft expected a daily limit while retaining an unenforceable seven-day expiry. The corrected gold now requires explicit removal of that expiry and adds a turn. This change follows native capability, not an observed model answer.

## Failures retained and repairs

The original deterministic run is preserved at `tmp/bm-semantic/product-journeys-deterministic-first.json` (byte SHA-256 `aecbe27b23201a87d52ca039e9df0e7e26b054c459ab25db7c3be9389d7a70ad`). It had 920 turns and 32 failing turns cascading from two defects. “Use a normal block” discarded the existing schedule; “Not 30 minutes” also removed the independently specified start. Their gold was preserved. The reducer now distinguishes a protection-style amendment from a fresh request; duration rejection no longer also parses its number as a clock. New regression tests check preserved facts, correction history, execution after a valid amendment, and no duplicate execution on acknowledgement.

The independent expiry finding also led to a runtime gate and user-facing explanation. A daily limit with a requested expiry cannot produce an action; an explicit “Keep it until I remove it” removes that constraint. The regression verifies that “Start now” and a generic yes do not remove it.

Final deterministic evidence: `tmp/bm-semantic/product-journeys-deterministic-final.json` has **925/925 passed in each of intent, slots, transition, provenance, decision, actions, and safety**; all 925 visible-equivalence checks remain unverified until independent review. Exit code 1 is intentional for that incomplete release gate. Semantic transition tests pass 89/89, oracle mutation tests reject or require fresh review for 42/42 mutations, and semantic extraction plus intelligence smoke tests pass. These figures establish functional conformance, not a tenfold product improvement or release eligibility.

## Reproduction and live evaluation

```powershell
node tools/build_bm_product_journeys.js
node tools/bm_semantic_replay.js --dataset tools/datasets/bm_product_journeys_v1.json --mode bm_final --repeats 1 --concurrency 16 --out tmp/bm-semantic/product-journeys-deterministic.json
```

For an explicitly configured live API environment, freeze source and dataset first. Run one mode and one repetition; additional repetitions do not count as distinct conversations. The replay requires `OPENAI_API_KEY` and the configured `OPENAI_MODEL`. Judge defaults to `gpt-5.6-sol` with low reasoning unless `BM_QUALITY_JUDGE_MODEL` is explicitly set.

```powershell
node tools/bm_semantic_replay.js --dataset tools/datasets/bm_product_journeys_v1.json --model --mode bm_final --repeats 1 --concurrency 8 --out tmp/bm-semantic/product-journeys-live.json
node tools/bm_sol_quality_judge.js --input tmp/bm-semantic/product-journeys-live.json --limit 925 --concurrency 8 --out tmp/bm-semantic/product-journeys-judge.json --oracle-reviews-out tmp/bm-semantic/product-journeys-oracle-reviews.json
```

Use these direct commands: the release wrapper's bounded replay/judge subprocess timeouts are unsuitable for this corpus. Judge checkpoints to its output and reuses matching input hashes on restart. Keep original model reports and judge bindings; do not rerun the model to obtain wording that fits existing review hashes. A complete judge report must cover all 925 turns and have no functional/hard failure.

Budget: 925 planner turns plus up to 925 first-attempt judge calls (judge retries can increase requests); the planner may issue multiple model requests per turn. At an illustrative 4.3-second planner-turn median and concurrency 8, planner-only wall time is about 9 minutes before variance. A judge averaging 3 seconds per turn takes about 6 minutes at concurrency 8 before variance. These are estimates, not measured runtimes for this corpus. Concurrency defaults to 1, accepts 1–8, preserves result order and deduplicates identical pending reviews. No dollar estimate is asserted: the current runners do not retain enough token-usage evidence to derive one reliably. Review the resulting source counts to distinguish active model extraction from grounded or deterministic fallback.
