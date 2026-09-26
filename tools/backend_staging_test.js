"use strict";
const assert = require("node:assert/strict");
const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const staging = require("./backend_staging");

const fixture = fs.mkdtempSync(path.join(os.tmpdir(), "blank-staging-test-"));
const sourceDir = path.join(fixture, "netlify", "functions");
fs.mkdirSync(sourceDir, { recursive: true });
for (const name of staging.ENTRIES) fs.writeFileSync(path.join(sourceDir, `${name}.js`), 'exports.handler = require("./dependency").handler;\n');
fs.writeFileSync(path.join(sourceDir, "dependency.js"), 'exports.handler = async () => ({statusCode:405});\n');
// These must never become independently exposed function entries.
fs.writeFileSync(path.join(sourceDir, "cron.js"), 'exports.config = {schedule:"* * * * *"};\n');
fs.writeFileSync(path.join(sourceDir, "whatsapp-agent.js"), "exports.handler = () => {};\n");
const names = [...staging.ENTRIES, "dependency", "cron", "whatsapp-agent"];
const tracked = names.map((name) => `netlify/functions/${name}.js`);
const commit = "a".repeat(40);
const deployId = "b".repeat(24);
const digest = (buffer) => crypto.createHash("sha256").update(buffer).digest("hex");
const args = { source: fixture, cli: "test-cli.js", site: staging.SITE_ID, deploy: false };
const bundler = { version: "test", zipFunctions: async (wrappers, target) => {
  staging.assertEntries(fs.readdirSync(wrappers).map((file) => file.replace(/\.js$/, "")));
  fs.mkdirSync(target);
  return staging.ENTRIES.map((name) => {
    assert(fs.readFileSync(path.join(wrappers, `${name}.js`), "utf8").includes(JSON.stringify(path.join(sourceDir, `${name}.js`))));
    const archive = path.join(target, `${name}.zip`);
    fs.writeFileSync(archive, `artifact:${name}`);
    return { name, path: archive, bundler: "esbuild", runtimeVersion: "nodejs22.x",
      inputs: [path.join(wrappers, `${name}.js`), path.join(sourceDir, `${name}.js`), path.join(sourceDir, "dependency.js")] };
  });
} };
const env = [
  { key: "SUPABASE_URL", scopes: ["functions"], values: [{ context: "production", value: `https://${staging.SUPABASE_REF}.supabase.co` }] },
  { key: "SUPABASE_SERVICE_ROLE_KEY", scopes: ["functions"], is_secret: true, values: [{ context: "production", value: "********************" }] },
];

function dependencies({ dirty = false, protectedSite = true, extraFunction = false } = {}) {
  const operations = [];
  let deployed = false;
  return { operations, token: "test-token", bundler,
    execute(command, argv, cwd) {
      operations.push({ command, argv, cwd });
      if (command === "git") {
        if (argv[0] === "status") return dirty ? " M netlify/functions/app-auth.js" : "";
        if (argv[0] === "ls-files") return tracked.join("\0");
        if (argv[0] === "branch") return "codex/backend-release-test";
        return argv[1] === "HEAD" ? commit : fixture;
      }
      assert.equal(argv[argv.indexOf("--site") + 1], staging.SITE_ID);
      assert(argv.includes("--prod") && argv.includes("--no-build") && argv.includes("--skip-functions-cache"));
      assert(!argv.includes("--context"), "CLI rejects --context together with --no-build");
      assert(!cwd.startsWith(fixture), "CLI must run outside the source worktree");
      deployed = true;
      return JSON.stringify({ site_id: staging.SITE_ID, deploy_id: deployId });
    },
    async fetcher(url) {
      operations.push({ url });
      if (url.startsWith(staging.SITE_URL)) return { status: protectedSite ? 401 : 200, body: { cancel: async () => {} } };
      let value;
      if (url.endsWith(`/sites/${staging.SITE_ID}`)) value = { id: staging.SITE_ID, ssl_url: staging.SITE_URL,
        account_id: "test-account", published_deploy: deployed ? { id: deployId } : null };
      else if (url.includes("/env?")) value = env;
      else if (url.endsWith(`/deploys/${deployId}`)) value = { site_id: staging.SITE_ID, state: "ready", function_schedules: [] };
      else if (url.endsWith("/functions")) value = [{ branch: null, functions: [
        ...staging.ENTRIES.map((name) => ({ n: name, d: digest(`artifact:${name}`), schedule: null })),
        ...(extraFunction ? [{ n: "cron", d: "bad", schedule: "* * * * *" }] : []),
      ] }];
      else throw new Error(`Unexpected read ${url}`);
      return { ok: true, json: async () => value };
    },
  };
}

(async () => {
  assert.equal(staging.parseArgs([]).deploy, false);
  assert.equal(staging.parseArgs(["--dry-run"]).deploy, false);
  assert.throws(() => staging.parseArgs(["--site-id", "59955668-9a9b-4979-a283-63fbf3115fe5", "--deploy"]), /Only the reserved/);
  assert.throws(() => staging.parseArgs(["--dry-run", "--deploy"]), /Choose/);
  assert.throws(() => staging.assertEntries([...staging.ENTRIES, "cron"]), /exactly/);
  assert.throws(() => staging.requireDeployable({ clean: true, branch: "main" }), /release/);
  const dry = dependencies();
  const packaged = await staging.main(args, dry);
  assert.equal(packaged.report.deploy_id, null);
  assert.equal(packaged.report.functions.length, 4);
  assert(packaged.report.source_inputs.some((input) => input.file.endsWith("dependency.js")));
  assert(dry.operations.every((operation) => operation.command === "git"), "dry-run performed a remote read or mutation");
  const scheduled = dependencies();
  scheduled.bundler = { ...bundler, zipFunctions: async (...values) => {
    const result = await bundler.zipFunctions(...values);
    result[0].schedule = "* * * * *";
    return result;
  } };
  await assert.rejects(() => staging.main(args, scheduled), /Scheduled, background/);
  assert(scheduled.operations.every((operation) => operation.command === "git"));
  const dirty = dependencies({ dirty: true });
  await assert.rejects(() => staging.main({ ...args, deploy: true }, dirty), /clean source/);
  assert(dirty.operations.every((operation) => operation.command === "git"));
  const exposed = dependencies({ protectedSite: false });
  await assert.rejects(() => staging.main({ ...args, deploy: true }, exposed), /not password-protected/);
  assert(!exposed.operations.some((operation) => operation.command && operation.command !== "git"), "deploy ran before privacy preflight");
  const changed = dependencies();
  const executeBeforeChange = changed.execute;
  let commitReads = 0;
  changed.execute = (command, argv, ...rest) => {
    const result = executeBeforeChange(command, argv, ...rest);
    if (command === "git" && argv[0] === "rev-parse" && argv[1] === "HEAD" && ++commitReads > 1) return "c".repeat(40);
    return result;
  };
  await assert.rejects(() => staging.main({ ...args, deploy: true }, changed), /Source changed/);
  assert(!changed.operations.some((operation) => operation.command && operation.command !== "git"));
  const wrongDatabase = structuredClone(env);
  wrongDatabase[0].values[0].value = "https://vhiikgyyfisejjwqtxfc.supabase.co";
  assert.throws(() => staging.validateEnvironment(wrongDatabase), /isolated/);
  assert.throws(() => staging.validateEnvironment([...env, { key: "APNS_AUTH_KEY", scopes: ["functions"], values: [{ context: "all", value: "blocked" }] }]), /Transport/);
  const completed = await staging.main({ ...args, deploy: true }, dependencies());
  assert.equal(completed.report.status, "private_deploy_verified");
  assert.equal(completed.report.remote_function_hashes_verified, true);
  assert.equal(completed.report.environment_preflight.service_key_ref_visible_and_verified, false, "masked keys must not be claimed as inspected");
  await assert.rejects(() => staging.main({ ...args, deploy: true }, dependencies({ extraFunction: true })), /exactly/);
  console.log("Private staging: no default remote calls, exact site/function allowlists, clean release source, password/database/transport preflights and remote digest verification passed");
})().catch((error) => { console.error(error); process.exitCode = 1; });
