# BM Training Plan

> Naming decision 2026-09-13: the assistant is now called **BM**, short for Blankmind. Technical legacy names such as `bai_*`, `bai-` and this filename remain temporarily for compatibility.

This is the operating plan for improving BM before production scale.

## Principle

BAI is not trained by changing model weights today. It improves through:

- Better prompts and routing.
- Better memory signals.
- Better action gating.
- Real user feedback and outcomes.
- Synthetic conversations that catch mistakes before users see them.
- Regression tests created from every important failure.

## Product Rule

BAI Web and BAI Messaging are the same digital wellness product.

They must share the same brain, tone, memory, context rules, and recommendation logic. The only difference is capability:

- Web can explain, plan, and preview value.
- App/messaging can route the user toward execution.
- Only the native app can request permissions and execute real blocking.

The evaluation must penalize any behavior that makes web feel like a weaker or different assistant.

## Scope Rule

Blanked only talks about digital wellness.

BAI must stay inside:

- Phone behavior.
- Screens.
- Apps.
- Scrolling.
- Focus and attention as affected by digital habits.
- Notifications.
- App blocking and phone boundaries.
- Screen-related sleep disruption.
- Wearable, Health, recovery, and activity signals only when they improve digital risk windows, phone-use predictions, or blocking decisions.

BAI must not provide generic:

- Training plans.
- Running plans.
- Nutrition advice.
- General sleep plans.
- Generic stress-management plans.
- Medical, therapy, or recovery advice.

If a generic wellness question is not connected to phone, screens, apps, or digital behavior, BAI redirects briefly to digital wellness and asks for the phone/screen part of the problem.

## Conversation Style Guide

Product direction from Guillem:

- Naturalness is the top priority.
- Do not add text just to make the answer feel complete.
- If BAI lacks context, it should ask one clear question and avoid giving advice too early.
- When the user's problem is app scrolling, distraction, focus blocks, phone boundaries or app control, BAI can naturally explain that Blanked App can solve it by blocking apps or creating a plan.
- When the user's problem is generic wellness, BAI does not answer as a generic wellness assistant. It redirects to the digital part.
- Web can explain and plan, but only Blanked App can ask for permissions and execute blocking.
- Do not recommend competing phone-control solutions such as built-in Screen Time or Digital Wellbeing.
- Avoid internal wording such as `context`, `old app`, `pattern`, `useful move`, `backend`, `schema`, or `I will not use the old app as context`.
- Do not use semicolons in user-visible BAI copy.
- Mention `Blanked App` when the app is relevant.
- Response length depends on the situation: short when a single question is enough, longer when useful detail genuinely helps.

## Training Moments

1. Before release
   - Run synthetic conversations.
   - Compare candidate models.
   - Catch context, tone, and action errors.

2. During real usage
   - Capture explicit feedback per response.
   - Capture outcomes: generated, activated, edited, cancelled, relapse_after, improved_after.
   - Store memory signals only when the user explicitly gives useful context.

3. After failures
   - Convert each important failure into a permanent eval case.
   - Examples: wrong context, forgotten detail, too much CTA, action when it should ask one more question.

4. Periodically
   - Review dashboard patterns.
   - Promote repeated findings into prompt/routing/memory changes.
   - Re-run model comparison before changing production model.

## Evaluation Owner

Evaluation is layered:

- Automated evaluator: catches contract, safety, context, action fit, and obvious tone problems.
- Guillem/product judgement: decides if the answer feels excellent, natural, and on-brand.
- Real users: validate whether the answer actually helped through feedback and outcomes.

For now, Guillem remains the final judge of taste. Automation reduces the number of bad answers he has to inspect.

## What The Benchmark Measures

Each candidate model is scored on:

- Context retention: does it remember important details from 2-3 turns ago?
- Natural tone: does it avoid robotic/product-template phrasing?
- Usefulness: does the answer actually help the user?
- Action fit: does it ask when information is missing and act when intent is clear?
- Channel fit: web explains/app CTA only when useful; messaging stays short and executable.
- Same-product consistency: web and messaging should feel like the same assistant.
- Safety/scope: stays inside digital wellness only.

## Release Gate

Before any BAI production deploy, run:

```bash
node tools/bai_release_gate.js
```

If `OPENAI_API_KEY` is available, the gate measures `gpt-5.6-luna`. If no API key is available, synthetic checks run in `--dry-run` so contracts and scenario generation can be validated without accidental model spend.

The gate runs:

- Legacy BAI eval: `tools/blanked_agent_eval.js`.
- Golden set: 25 deterministic conversations, seed `20260910`.
- Wide synthetic suite: 125 deterministic conversations by default.
- BAI web/app smoke.
- WhatsApp smoke.
- SMS/voice smoke.

Blocking rule:

- `real_behavior_issue` must be `0`.
- Weighted pass rate must be at least `99%`.
- `rubric_miss` is reported but does not block release unless explicitly capped.

Failure classes:

- `real_behavior_issue`: safety, tone, copy quality, same-product framing, wrong context, action fit, or channel fit.
- `rubric_miss`: strict context/editorial expectations where the answer may still be usable but misses the exact expected shape.

For a full model run with saved reports:

```bash
node tools/bai_release_gate.js --save --count 125
```

For a cheap local verification:

```bash
node tools/bai_release_gate.js --quick
```

## Synthetic Conversation Suite

Use `tools/bai_synthetic_conversation_suite.js` for the deterministic pre-production loop.

The suite generates deterministic multi-turn conversations across:

- Context retention.
- User corrections.
- Web/app same-product consistency.
- Messaging brevity.
- Digital wellness scope.
- Action fit.
- Scope and privacy.
- Spanish.
- Reusable modes.

The important number is not only full conversation pass count. The report also gives a weighted score and failures by group/dimension, because strict synthetic checks are intentionally sharper than normal user-facing evals.

Current required coverage:

- Golden set: 25 conversations before every BAI deploy.
- Wide suite: 100-150 conversations before every BAI deploy. Default gate count is 125.
- Reports split failures into `real_behavior_issue` and `rubric_miss`.

Latest historical cycle:

- Baseline after adding the suite: 24/50 strict conversations, 718/752, 95.5%.
- After the first debugging pass: 43/50 strict conversations, 745/752, 99.1%.
- After applying Guillem's editorial criteria: 45/50 strict conversations, 747/752, 99.3%.
- Zero failures in safety, natural tone, copy quality, same-product consistency, wrong context, action fit, and channel fit.
- Remaining failures are 1-point context/editorial misses where the answer is usable but not yet exact enough for the expected conversation shape.
- Human-readable review file: `docs/BAI_SYNTHETIC_CONVERSATIONS_REVIEW.md`.

Latest real gate run:

- Date: 2026-09-11.
- Model: `gpt-5.6-luna`.
- Scope: digital wellness only.
- Legacy eval: 111/111.
- Golden set: 25/25, 384/384, 100%, 0 `real_behavior_issue`, 0 `rubric_miss`.
- Wide suite: 125/125, 1880/1880, 100%, 0 `real_behavior_issue`, 0 `rubric_miss`.
- Smokes: BAI web/app, WhatsApp, SMS/voice and digital-wellness wearable loop all passed.
- Android compile and unit tests passed.
- Digital scope cases verify that generic sleep/running/energy/stress prompts redirect to digital wellness instead of giving generic plans.
- Generated recommendations now carry a stable `recommendation_id`; refreshes are idempotent and activations feed `bai_user_plan_outcomes` from Android/iOS.
- Production release: migration applied in Supabase `blank-membership`; Netlify `getblank` deployed and remotely smoke-tested; Supabase Edge `digital-wellness-features` also deployed. Both production paths are live.

Fixes from the debugging passes:

- Short timing replies such as "Usually 9" now use recent conversation context and can create an `apply_schedule` action.
- Existing mode activation is prioritized before generic sleep-context questions, so "Start Sleep mode for 45 minutes" activates the saved mode.
- Generic "social media" only maps to Social mode when a saved/known mode context exists; otherwise BAI asks for missing setup/context.
- `Reels` is recognized as an app target.
- Immediate block copy is less template-like.
- Synthetic scoring now allows good concise messaging answers without forcing unnecessary app-name repetition.
- If context is missing, BAI now asks one clear question instead of adding advice too early.
- Web and messaging keep the same product logic: web can plan, Blanked App executes because it has permissions.
- User-visible copy avoids semicolons, internal phrasing, and competing phone-control suggestions.
- When Blanked can solve the user's app/scroll/focus problem, BAI naturally recommends Blanked App blocks or plans.

## Candidate Models

Previous production model:

- `gpt-4.1-mini`

Official model:

- `gpt-5.6-luna`

Secondary candidate:

- `gpt-5-mini`

Decision rule:

Do not switch production just because a model is newer or cheaper. Switch only if the candidate wins on quality enough that the user experience improves without unacceptable latency or cost.

## Rollout

Recommended rollout:

1. Run 10-20 benchmark conversations locally.
2. Inspect failures manually.
3. Fix prompts/gates/memory before blaming the model.
4. Run 50 synthetic conversations.
5. If `gpt-5.6-luna` wins, test it behind env var in staging/preview.
6. Move production only after smoke tests and sample review pass.

## Next Work

The implementation and release cycle is complete. The remaining learning step is operational rather than model-weight training:

1. Accumulate real-user activations, completions, breaks and feedback.
2. Review the learning dashboard periodically and promote only repeated real behavior issues into permanent evals.
3. Do not fabricate training volume or train model weights yet.
