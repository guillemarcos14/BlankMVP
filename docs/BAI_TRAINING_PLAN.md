# BAI Training Plan

This is the operating plan for improving Blanked AI before production scale.

## Principle

BAI is not trained by changing model weights today. It improves through:

- Better prompts and routing.
- Better memory signals.
- Better action gating.
- Real user feedback and outcomes.
- Synthetic conversations that catch mistakes before users see them.
- Regression tests created from every important failure.

## Product Rule

BAI Web and BAI Messaging are the same product.

They must share the same brain, tone, memory, context rules, and recommendation logic. The only difference is capability:

- Web can explain, plan, and preview value.
- App/messaging can route the user toward execution.
- Only the native app can request permissions and execute real blocking.

The evaluation must penalize any behavior that makes web feel like a weaker or different assistant.

## Conversation Style Guide

Product direction from Guillem:

- Naturalness is the top priority.
- Do not add text just to make the answer feel complete.
- If BAI lacks context, it should ask one clear question and avoid giving advice too early.
- When the user's problem is app scrolling, distraction, focus blocks, phone boundaries or app control, BAI can naturally explain that Blanked App can solve it by blocking apps or creating a plan.
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
- Safety/scope: stays inside wellness and digital wellness.

## Synthetic Conversation Suite

Use `tools/bai_synthetic_conversation_suite.js` for the 50-conversation pre-production loop.

The suite generates deterministic multi-turn conversations across:

- Context retention.
- User corrections.
- Web/app same-product consistency.
- Messaging brevity.
- General wellness.
- Action fit.
- Scope and privacy.
- Spanish.
- Reusable modes.

The important number is not only full conversation pass count. The report also gives a weighted score and failures by group/dimension, because strict synthetic checks are intentionally sharper than normal user-facing evals.

Latest cycle:

- Baseline after adding the suite: 24/50 strict conversations, 718/752, 95.5%.
- After the first debugging pass: 43/50 strict conversations, 745/752, 99.1%.
- After applying Guillem's editorial criteria: 45/50 strict conversations, 747/752, 99.3%.
- Zero failures in safety, natural tone, copy quality, same-product consistency, wrong context, action fit, and channel fit.
- Remaining failures are 1-point context/editorial misses where the answer is usable but not yet exact enough for the expected conversation shape.
- Human-readable review file: `docs/BAI_SYNTHETIC_CONVERSATIONS_REVIEW.md`.

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

Next debugging pass:

1. Run 100-150 synthetic conversations with the same seed discipline.
2. Split failures into real behavior issues vs rubric misses.
3. Promote only real repeated failures into permanent eval cases.
4. Build a small "golden set" of 25 conversations that must never regress before production pushes.
