const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { spawnSync } = require('node:child_process');

// Compile the production transport, rather than a JavaScript copy of its logic.
// Keychain and the install ID are replaced with process-local test fixtures.
const source = fs.readFileSync(path.join(__dirname, '../ios/Blank/Blank/AssistantAppView.swift'), 'utf8').replace(/\r\n/g, '\n');
const start = source.indexOf('struct AssistantAppTurn:');
const end = source.indexOf('@MainActor\nfinal class AssistantSpeechInput');
if (start < 0 || end < start) throw new Error('Assistant client source boundaries changed');
const test = fs.readFileSync(path.join(__dirname, 'assistant_client_test.swift'), 'utf8');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'blank-assistant-client-'));
try {
  const file = path.join(temporary, 'AssistantClientTests.swift');
  const binary = path.join(temporary, 'assistant-client-tests');
  fs.writeFileSync(file, `import Foundation\n${source.slice(start, end)}\n${test}`);
  const compiled = spawnSync('swiftc', ['-swift-version', '5', '-parse-as-library', file, '-o', binary], { encoding: 'utf8' });
  if (compiled.error) throw new Error(`Native client tests require Swift on macOS: ${compiled.error.message}`);
  if (compiled.status !== 0) throw new Error(compiled.stderr || compiled.stdout);
  const result = spawnSync(binary, [], { encoding: 'utf8' });
  process.stdout.write(result.stdout || '');
  process.stderr.write(result.stderr || '');
  if (result.error) throw result.error;
  process.exitCode = result.status || 0;
} finally {
  fs.rmSync(temporary, { recursive: true, force: true });
}
