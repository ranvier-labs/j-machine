import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile, access, readdir } from 'node:fs/promises';
import { TOPICS, CONTEXT_TOPICS, blocks, inline, linkTarget, topicLocation, searchTopics, ReadingHistory } from '../site/documentation/manual.js';
import { TileLayout, leaf, split } from '../site/shell/layout.js';

test('every manual link resolves to a real topic, section, seeded file, or IDE action', async () => {
  const app = await readFile(new URL('../site/app.js', import.meta.url), 'utf8');
  const commands = new Set([...app.matchAll(/register\('([^']+)'/g)].map(match => match[1]));
  for (const file of await readdir(new URL('../site/windows/', import.meta.url))) {
    const source = await readFile(new URL('../site/windows/' + file, import.meta.url), 'utf8');
    for (const match of source.matchAll(/id:\s*'([^']+)'/g)) commands.add('window-' + match[1]);
  }
  for (const match of app.matchAll(/^  ([a-z]+): \(\) => split/gm)) commands.add('layout-' + match[1]);
  const seeded = new Set(['/home/user/main.c', '/home/user/build.jm', '/home/user/build-graphics.jm']);
  const ids = new Set();
  let checked = 0;
  for (const topic of TOPICS) {
    assert.ok(!ids.has(topic.id), 'duplicate topic: ' + topic.id); ids.add(topic.id);
    const sections = blocks(topic.body), headings = sections.filter(b => b.type === 'heading');
    assert.equal(new Set(headings.map(h => h.id)).size, headings.length, 'duplicate heading in ' + topic.id);
    for (const block of sections) for (const line of block.type === 'list' ? block.items : block.type === 'code' ? [] : [block.text]) {
      for (const part of inline(line).filter(p => p.type === 'link')) {
        const target = linkTarget(part.href); assert.ok(target, topic.id + ': ' + part.href); checked++;
        if (target.type === 'command') assert.ok(commands.has(target.command), 'missing command: ' + target.command);
        if (target.type === 'file' && !seeded.has(target.path)) {
          assert.ok(target.path.startsWith('/examples/'));
          await access(new URL('../../compiler/examples/' + target.path.slice('/examples/'.length), import.meta.url));
        }
      }
    }
  }
  assert.ok(checked > 80, 'validate the full manual, not an empty parse');
  for (const topic of Object.values(CONTEXT_TOPICS)) assert.ok(topicLocation(topic));
});

test('search ranks titles, requires every term, and supports topic aliases and anchors', () => {
  assert.equal(searchTopics('project builds')[0].id, 'build');
  assert.ok(searchTopics('mailbox reply').some(t => t.id === 'packets'));
  assert.equal(searchTopics('nonexistent-zqx-topic').length, 0);
  assert.equal(searchTopics('').length, TOPICS.length);
  assert.deepEqual(topicLocation('BUILD#graph-syntax'), { topic: 'build', anchor: 'graph-syntax' });
  assert.equal(topicLocation('commands').topic, 'listener');
  assert.equal(topicLocation('build#missing-section'), null);
  assert.equal(linkTarget('javascript:alert(1)'), null);
  assert.equal(linkTarget('https://example.com'), null);
  assert.equal(linkTarget('command:window-build;run'), null);
});

test('reading history restores scroll, drops forward branches, rejects invalid visits, and stays bounded', () => {
  const history = new ReadingHistory(3);
  history.remember(125); history.visit('build'); history.remember(640);
  history.visit('build#graph-syntax'); history.remember(200);
  assert.equal(history.move(-1), true); assert.equal(history.current.scroll, 640);
  history.visit('packets'); assert.equal(history.canForward, false);
  const before = structuredClone(history.entries);
  assert.equal(history.visit('unknown'), false); assert.deepEqual(history.entries, before);
  history.visit('display'); assert.equal(history.entries.length, 3); assert.equal(history.canForward, false);
  history.visit('build'); assert.equal(history.current.scroll, 640);
  while (history.move(-1)) {}
  assert.equal(history.canBack, false);
});

test('manual parsing preserves executable examples verbatim and never treats code as links', () => {
  const topic = TOPICS.find(t => t.id === 'build');
  const code = blocks(topic.body).filter(b => b.type === 'code');
  assert.equal(code.length, 2);
  assert.match(code[0].text, /\n  nodes = 2\n/);
  assert.equal(code[1].language, 'listener');
  assert.equal(code[1].text.split('\n')[0], 'use-build /home/user/build.jm');
  const parts = inline('Read [builds](doc:build) and `[raw](doc:bad)`.');
  assert.equal(parts.filter(p => p.type === 'link').length, 1);
  assert.equal(parts.find(p => p.type === 'code').text, '[raw](doc:bad)');
});

test('opening documentation beside the desktop preserves and restores the existing arrangement', () => {
  const tree = split('x', .2, leaf('files'), split('y', .7, leaf('editor'), leaf('listener')));
  const layout = new TileLayout(tree);
  layout.open('documentation', { atRoot: true, edge: 'right', ratio: .45 });
  assert.deepEqual(layout.tree.first, tree);
  assert.equal(layout.tree.ratio, .45);
  assert.equal(layout.tree.second.id, 'documentation');
  layout.close('documentation'); assert.deepEqual(layout.tree, tree);
});
