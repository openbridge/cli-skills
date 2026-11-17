/**
 * OpenCode plugin: config registration + bootstrap injection.
 *
 * Drives the plugin's two hooks with fabricated harness input. This proves the
 * code does what it intends; it does NOT prove OpenCode loads the plugin or
 * calls these hooks. Only a live session does that.
 *
 * The case worth protecting: OpenCode reloads messages from its DB on every
 * agent step — not every turn — and can pass an already-transformed array back
 * through the transform hook. Without the marker guard the bootstrap stacks a
 * fresh copy on every step until the context window is full of it.
 */
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

// Identity comes from package.json, never a literal: scripts/identity.sh rename
// moves this plugin's filename and rewrites the name inside it, and a test that
// hardcoded either would fail for every fork on its first day.
const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const pkg = JSON.parse(fs.readFileSync(path.join(repoRoot, 'package.json'), 'utf8'));
const NAME = pkg.name;
const { ObSkillsPlugin } = await import(path.join(repoRoot, pkg.main));

let failures = 0;
const test = async (name, fn) => {
  try { await fn(); console.log(`  ok  ${name}`); }
  catch (e) { failures++; console.error(`FAIL: ${name}\n      ${e.message}`); }
};

console.log('test-opencode-plugin: config hook + message transform');

const plugin = await ObSkillsPlugin({});
const transform = plugin['experimental.chat.messages.transform'];

const freshMessages = () => ({
  messages: [
    { info: { role: 'user' }, parts: [{ type: 'text', text: 'hello', id: 'p1' }] },
    { info: { role: 'assistant' }, parts: [{ type: 'text', text: 'hi' }] },
  ],
});

await test('config registers the skills directory', async () => {
  const config = {};
  await plugin.config(config);
  assert.equal(config.skills.paths.length, 1);
  assert.ok(config.skills.paths[0].endsWith('/skills'), 'path should end in /skills');
});

await test('config is idempotent across repeated calls', async () => {
  const config = {};
  await plugin.config(config);
  await plugin.config(config);
  await plugin.config(config);
  assert.equal(config.skills.paths.length, 1, 'skills path was appended more than once');
});

await test('config preserves paths another plugin registered', async () => {
  const config = { skills: { paths: ['/somewhere/else'] } };
  await plugin.config(config);
  assert.equal(config.skills.paths.length, 2);
  assert.equal(config.skills.paths[0], '/somewhere/else');
});

await test('transform injects the bootstrap ahead of the first user message', async () => {
  const out = freshMessages();
  await transform({}, out);
  const parts = out.messages[0].parts;
  assert.equal(parts.length, 2);
  assert.ok(parts[0].text.includes('EXTREMELY_IMPORTANT'), 'bootstrap not first');
  assert.equal(parts[1].text, 'hello', 'original message content was lost');
});

await test('transform copies the reference part\'s fields', async () => {
  const out = freshMessages();
  await transform({}, out);
  assert.equal(out.messages[0].parts[0].id, 'p1', 'injected part did not inherit sibling fields');
});

await test('repeated transforms do not stack copies', async () => {
  const out = freshMessages();
  await transform({}, out);
  await transform({}, out);
  await transform({}, out);
  assert.equal(out.messages[0].parts.length, 2, 'bootstrap was injected more than once');
});

await test('transform is a no-op with no user message', async () => {
  const out = { messages: [{ info: { role: 'assistant' }, parts: [{ type: 'text', text: 'x' }] }] };
  await transform({}, out);
  assert.equal(out.messages[0].parts.length, 1);
});

await test('transform is a no-op on an empty message array', async () => {
  const out = { messages: [] };
  await transform({}, out);
  assert.equal(out.messages.length, 0);
});

await test('bootstrap names the collection and carries the tool mapping', async () => {
  const out = freshMessages();
  await transform({}, out);
  const text = out.messages[0].parts[0].text;
  assert.ok(text.includes(`You have ${NAME}.`), 'collection name missing');
  for (const tool of ['todowrite', 'apply_patch', 'webfetch', 'skill']) {
    assert.ok(text.includes(tool), `tool mapping missing ${tool}`);
  }
});

await test('bootstrap strips frontmatter', async () => {
  const out = freshMessages();
  await transform({}, out);
  const text = out.messages[0].parts[0].text;
  assert.ok(!text.includes('description: Use when starting any conversation'),
    'frontmatter leaked into the injected bootstrap');
});

if (failures) { console.error(`FAILED: ${failures} check(s)`); process.exit(1); }
console.log('PASS: test-opencode-plugin');
