"use strict";

const assert = require("assert");
const {
  validateContract,
  validateCommand,
  globToRegExp,
} = require("./product_harness");

validateContract({
  schema_version: 1,
  id: "test",
  objective: "test objective",
  scope: ["tools/**"],
  acceptance: ["tests pass"],
  context: { process: "Blank Brain/PROCESOS/desarrollo.md", files: [] },
  validation: {
    max_repair_attempts: 1,
    repair_commands: [{ name: "repair", run: "node --check tools/product_harness.js" }],
    commands: [{ name: "check", run: "node --check tools/product_harness.js" }],
  },
  memory_updates: [],
});

assert.strictEqual(validateCommand("node --check tools/product_harness.js", "test"), "node --check tools/product_harness.js");
assert.throws(() => validateCommand("git reset --hard", "unsafe"), /dangerous_command_not_allowed/);
assert.throws(() => validateCommand("node test.js && del file", "operator"), /shell_operator_not_allowed/);
assert.throws(() => validateCommand("node --eval console.log(1)", "inline_node"), /dangerous_command_not_allowed/);
assert.throws(() => validateCommand("node test.js & del file", "windows_operator"), /shell_operator_not_allowed/);
assert.ok(globToRegExp("netlify/functions/**").test("netlify/functions/blanked-agent.js"));
assert.ok(!globToRegExp("netlify/functions/**").test("tools/product_harness.js"));

console.log("product_harness_test: ok");
