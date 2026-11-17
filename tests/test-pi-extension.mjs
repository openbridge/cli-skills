/**
 * Pi extension: lifecycle flags + compaction-aware insertion.
 *
 * Pi's `context` event fires every turn, but the bootstrap only needs to be
 * present once per context window. The extension arms on session_start and
 * session_compact and disarms on agent_end. Get that wrong in either direction
 * and you either re-inject every turn (token burn) or lose the bootstrap after
 * a compaction (silent behaviour change deep into a long session).
 *
 * The extension is TypeScript that Pi runs directly. Node can execute it with
 * type stripping, but the type-only import of Pi's own package cannot resolve
 * here — it is erased at runtime anyway, so the test strips it.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
// Identity from package.json, never a literal — see test-opencode-plugin.mjs.
const pkg = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
const NAME = pkg.name;
const EXT_REL = pkg.pi.extensions[0].replace(/^\.\//, '');

const major = Number(process.versions.node.split('.')[0]);
if (major < 22) {
  console.log(`SKIP: test-pi-extension (node ${process.versions.node} lacks type stripping)`);
  process.exit(0);
}

// Mirror the extension into a temp tree with the type-only import removed, and
// with skills/ alongside so its relative bootstrap path still resolves.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), `${NAME}-pi-`));
process.on('exit', () => fs.rmSync(tmp, { recursive: true, force: true }));
fs.mkdirSync(path.join(tmp, '.pi/extensions'), { recursive: true });
fs.cpSync(path.join(repoRoot, 'skills'), path.join(tmp, 'skills'), { recursive: true });
const src = fs.readFileSync(path.join(repoRoot, EXT_REL), 'utf8')
  .split('\n').filter((l) => !l.startsWith('import type')).join('\n')
  .replace('pi: ExtensionAPI', 'pi: any');
const extPath = path.join(tmp, EXT_REL);
fs.writeFileSync(extPath, src);

const mod = await import(extPath);

let failures = 0;
const test = async (name, fn) => {
  try { await fn(); console.log(`  ok  ${name}`); }
  catch (e) { failures++; console.error(`FAIL: ${name}\n      ${e.message}`); }
};

console.log('test-pi-extension: lifecycle + compaction-aware injection');

// Each case gets its own extension instance: the arm/disarm flag is per-instance
// state, and sharing it across cases would let one test mask another.
const mount = () => {
  const handlers = {};
  mod.default({ on: (evt, fn) => { handlers[evt] = fn; } });
  return handlers;
};
const userMsg = (text) => ({ role: 'user', content: [{ type: 'text', text }] });
const summary = () => ({ role: 'compactionSummary', content: [{ type: 'text', text: 's' }] });

await test('registers every lifecycle event it depends on', async () => {
  const h = mount();
  for (const evt of ['resources_discover', 'session_start', 'session_compact', 'agent_end', 'context']) {
    assert.ok(h[evt], `missing handler for ${evt}`);
  }
});

await test('resources_discover returns the skills directory', async () => {
  const h = mount();
  const { skillPaths } = await h.resources_discover();
  assert.equal(skillPaths.length, 1);
  assert.ok(skillPaths[0].endsWith('/skills'));
});

await test('injects on a fresh session', async () => {
  const h = mount();
  await h.session_start();
  const r = await h.context({ messages: [userMsg('hello')] });
  assert.equal(r.messages.length, 2);
  assert.ok(r.messages[0].content[0].text.includes('EXTREMELY_IMPORTANT'));
  assert.equal(r.messages[1].content[0].text, 'hello');
});

await test('does not re-inject into a window that already has the bootstrap', async () => {
  const h = mount();
  await h.session_start();
  const r = await h.context({ messages: [userMsg('hello')] });
  const again = await h.context({ messages: r.messages });
  assert.equal(again, undefined, 'returned a mutation for an already-bootstrapped window');
});

await test('agent_end disarms injection', async () => {
  const h = mount();
  await h.session_start();
  await h.agent_end();
  assert.equal(await h.context({ messages: [userMsg('hello')] }), undefined);
});

await test('session_compact re-arms injection', async () => {
  const h = mount();
  await h.session_start();
  await h.agent_end();
  await h.session_compact();
  const r = await h.context({ messages: [userMsg('next')] });
  assert.ok(r, 'bootstrap was not re-injected after compaction');
});

await test('bootstrap lands after compaction summaries, not before them', async () => {
  const h = mount();
  await h.session_compact();
  const r = await h.context({ messages: [summary(), summary(), userMsg('next')] });
  assert.deepEqual(
    r.messages.map((m) => m.role),
    ['compactionSummary', 'compactionSummary', 'user', 'user'],
    'bootstrap was inserted in the wrong position relative to summaries',
  );
  assert.ok(r.messages[2].content[0].text.includes('EXTREMELY_IMPORTANT'));
});

await test('bootstrap names the collection and carries the Pi tool mapping', async () => {
  const h = mount();
  await h.session_start();
  const r = await h.context({ messages: [userMsg('hello')] });
  const text = r.messages[0].content[0].text;
  assert.ok(text.includes(`You have ${NAME}.`));
  assert.ok(text.includes('Pi tool mapping'));
  // Pi has no Task tool; the mapping must say so rather than leave the model guessing.
  assert.ok(text.includes('Task'), 'mapping should warn against inventing Task calls');
});

if (failures) { console.error(`FAILED: ${failures} check(s)`); process.exit(1); }
console.log('PASS: test-pi-extension');
