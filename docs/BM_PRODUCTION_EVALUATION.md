# BM production conversation evaluation

`tools/bm_production_conversation_eval.js` exercises the deployed `blanked-agent` endpoint with the active model and preserves the last eight user/assistant turns between messages. It is intentionally separate from the deterministic release gate: running it spends model/API budget and checks the behavior the user actually receives.

## Run

```powershell
node tools/bm_production_conversation_eval.js --repeats 2 --out tmp/bm-production-eval/latest.json
```

Use `--url` for a different deployed endpoint. The evaluator never calls Twilio, sends WhatsApp/SMS messages, changes Supabase, or executes an app action. It only posts planning requests to the direct BM function.

## Release meaning

The evaluator passes only when the active model is observed at least once and all traces preserve the conversation contract. It checks that BM:

- keeps app and time context across the morning scroll conversation;
- does not invent a daily limit or expose a link before the window is complete and confirmed;
- requires a concrete amount for daily limits;
- keeps small talk out of the product route;
- refuses execution when app presence is stale;
- preserves the bedtime follow-up context.

The result is evidence for the deployed endpoint, not a guarantee of every possible conversation. New real regressions must become a trace or invariant before the next release.
