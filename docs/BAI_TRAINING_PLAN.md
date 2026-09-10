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

## Candidate Models

Current production model:

- `gpt-4.1-mini`

Primary candidate:

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

