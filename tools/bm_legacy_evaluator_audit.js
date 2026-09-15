"use strict";

const assert = require("assert");
const fs = require("fs");
const path = require("path");
const { assertPlan, qualityScore, utilityScore } = require("./blanked_agent_eval");
const { digest } = require("./bm_semantic_oracle");
const cases = require("./blanked_agent_eval_cases.json");

function seed(testCase) {
  return {
    intent: testCase.expect.intent,
    title: "Block selected apps",
    message_text: "Review Instagram from 10:00 PM to 6:00 AM. The schedule needs your confirmation in Blankmind.",
    response_text: "Block Instagram from 10:00 PM to 6:00 AM. Review the schedule in Blankmind.",
    bullets: ["Read: Instagram was the concern.", "Pattern: protect the specified window."],
    actions: [{ type: "apply_schedule", start_minute: 1320, end_minute: 360, weekdays: [1, 2, 3, 4, 5, 6, 7], ...testCase.expect.first_action }],
    blocking_ready: true,
    blocking_data: { apps: ["Instagram"], action: "strict_block", start: 1320, end: 360, recurrence: "daily" },
    blocking_missing_fields: [],
    requires_selected_apps: true, requires_screen_time_authorization: true,
  };
}
function main() {
  const originalCase = cases.find(item => item.id === "bare_time_window_after_sleep_context_crosses_midnight");
  assert.ok(originalCase, "original legacy fixture exists");
  const original = seed(originalCase);
  assertPlan(originalCase, original);
  const mutations = [
    ["visible_window_and_app_contradict_action", "The visible sentence contains one expected time token but claims a different app/window and completed execution.", plan => { plan.message_text = "10:00 PM is irrelevant. I have blocked TikTok from 2:00 AM to 3:00 AM already."; }],
    ["canonical_data_contradicts_action", "blocking_data differs from the scheduled action; non-null checks accept both.", plan => { plan.blocking_data.apps = ["TikTok"]; plan.blocking_data.start = 1; plan.blocking_data.end = 2; }],
    ["unasserted_recurrence_changed", "The original fixture checks first_action start/end only. A weekly schedule mutation passes.", plan => { plan.actions[0].weekdays = [2]; }],
    ["blocking_contract_skips_permission_assertions", "The blocking-contract branch returns before checking explicit requires_* expectations.", plan => { plan.requires_selected_apps = false; plan.requires_screen_time_authorization = false; }],
    ["keyword_word_salad", "Expected keywords and valid structured fields are sufficient for unrelated/absurd visible content.", plan => { plan.message_text = "10:00 PM. Instagram. Purple bananas eat the schedule while invisible chairs protect algebra."; }],
    ["speech_surface_contradiction", "speech_text/followup_text are not inspected by visibleText or userVisibleText in the legacy evaluator.", plan => { plan.speech_text = "I have blocked Reddit for 4 hours starting at 2:00 AM."; plan.followup_text = "All apps are already blocked permanently."; }],
  ];
  const results = mutations.map(([id, explanation, mutate]) => {
    const plan = structuredClone(original);
    const testCase = structuredClone(originalCase);
    if (id === "blocking_contract_skips_permission_assertions") {
      testCase.expect.requires_selected_apps = true;
      testCase.expect.requires_screen_time_authorization = true;
    }
    mutate(plan);
    let accepted = true; let error = null;
    try { assertPlan(testCase, plan); } catch (caught) { accepted = false; error = caught.message; }
    return { id, source_case: originalCase.id, original_fixture_unchanged: id !== "blocking_contract_skips_permission_assertions", accepted_by_actual_legacy_assertPlan: accepted, explanation, quality_score: qualityScore(plan), utility_score: utilityScore(plan), error, test_case: testCase, mutated_plan: plan };
  });
  const report = { evaluator: "legacy-actual-assertPlan-mutation-audit-v1", generated_at: new Date().toISOString(), assert_source_sha256: digest(assertPlan.toString()), original_case: originalCase, seed: original, false_positives: results.filter(item => item.accepted_by_actual_legacy_assertPlan).length, total: results.length, results,
    interpretation: "These are constructed counterexamples accepted by the actual legacy evaluator, not claims that the live model emitted these answers. Five use unchanged original fixture expectations; the permission counterexample adds expected permission fields to demonstrate the branch skips them." };
  const at = process.argv.indexOf("--out");
  const out = at >= 0 ? process.argv[at + 1] : "tmp/bm-semantic/legacy-false-positives.json";
  fs.mkdirSync(path.dirname(out), { recursive: true });
  fs.writeFileSync(out, `${JSON.stringify(report, null, 2)}\n`);
  console.log(`Actual legacy assertPlan accepted ${report.false_positives}/${report.total} deliberately invalid plans. Report: ${path.resolve(out)}`);
  assert.equal(report.false_positives, report.total, "audit counterexamples must remain reproducible; a repaired evaluator should update this evidence, not weaken gates");
}
if (require.main === module) main();
