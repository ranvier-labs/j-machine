import test from 'node:test';
import assert from 'node:assert/strict';
import { CommandRegistry, matchesKey } from '../site/shell/commands.js';
import { TileLayout, leaf, split } from '../site/shell/layout.js';
const event = (key, modifiers = {}) => ({ key, code: `Key${key.toUpperCase()}`, preventDefault() { this.defaultPrevented = true; }, ...modifiers });
test('named commands share dispatch, scoped keys, and a configurable keymap', () => {
  const registry = new CommandRegistry(), calls = [];
  registry.register({ id:'build', label:'Build', keys:['Mod+b'], run:() => calls.push('build') });
  registry.register({ id:'next-event', label:'Next event', scope:'history', keys:['Alt+ArrowRight'], run:() => calls.push('next') });
  assert.equal(registry.handle(event('b',{metaKey:true}),'editor'),true);
  assert.equal(registry.handle(event('ArrowRight',{altKey:true}),'editor'),false);
  assert.equal(registry.handle(event('ArrowRight',{altKey:true}),'history'),true);
  registry.run('build'); registry.entries('editor').find(c=>c.id==='build').run();
  assert.deepEqual(calls,['build','next','build','build']);
  registry.loadKeymap('{"version":1,"bindings":{"build":["Ctrl+Alt+b"]}}');
  assert.equal(registry.handle(event('b',{metaKey:true}),'editor'),false);
  assert.equal(registry.handle(event('b',{ctrlKey:true,altKey:true}),'editor'),true);
  assert.throws(()=>registry.loadKeymap('{"version":1,"bindings":{"missing":["x"]}}'),/Unknown/);
  assert.equal(registry.handle(event('b',{ctrlKey:true,altKey:true,isComposing:true}),'editor'),false);
  assert.ok(matchesKey('Alt+x',event('≈',{altKey:true,code:'KeyX'})));
});
test('keyboard resizing finds the closest split on each axis and preserves all windows', () => {
  const layout = new TileLayout(split('x',.5,leaf('files'),split('y',.5,leaf('editor'),leaf('listener'))));
  layout.focused='listener'; layout.resizeFocused('y',.1); assert.equal(layout.tree.second.ratio,.4);
  layout.resizeFocused('x',.1); assert.equal(layout.tree.ratio,.4);
  layout.resizeFocused('x',20); assert.equal(layout.tree.ratio,.12);
  assert.equal(layout.focused,'listener');
  assert.equal(layout.cycle(-1),'editor');
});

test('buttons, palette entries, and keyboard dispatch share dynamic availability and errors', () => {
  let running = false, allowed = false, calls = 0; const errors = [];
  const registry = new CommandRegistry({execute:run=>{try{return run();}catch(error){errors.push(error.message);}}});
  registry.register({id:'run',label:'Run',keys:['F5'],state:()=>({label:running?'Pause':'Run',enabled:allowed,reason:allowed?'':'Load an image first.'}),run:()=>{calls++;running=!running;}});
  const entry = registry.entries()[0];
  assert.equal(entry.enabled, registry.state('run').enabled);
  assert.match(entry.detail, /Load an image first/);
  registry.handle(event('F5')); entry.run(); registry.run('run');
  assert.equal(calls,0); assert.deepEqual(errors,Array(3).fill('Load an image first.'));
  allowed = true; entry.run(); assert.equal(calls,1);
  assert.equal(registry.state('run').label,'Pause'); assert.equal(entry.state().label,'Pause');
});

test('menu membership is explicit and independent of command name prefixes', () => {
  const registry = new CommandRegistry();
  for(const command of [{id:'window-editor',menu:'windows'},{id:'window-close',menu:'layout'},{id:'focus-left',menu:'layout'},{id:'resize-right',menu:'layout'},{id:'layout-editing',menu:'layout'},{id:'window-controls'}]) registry.register({...command,label:command.id,run(){}});
  assert.deepEqual(registry.entries(undefined,{menu:'windows'}).map(c=>c.id),['window-editor']);
  assert.deepEqual(registry.entries(undefined,{menu:'layout'}).map(c=>c.id),['window-close','focus-left','resize-right','layout-editing']);
  assert.equal(registry.entries(undefined,{allScopes:true}).length,6);
});

test('a keymap from an earlier release loads through aliases and reports unknown commands', () => {
  const registry = new CommandRegistry();
  registry.register({ id: 'window-geometry', label: 'Routing geometry', run() {}, keys: [] });
  registry.register({ id: 'save', label: 'Save', run() {}, keys: ['Mod+s'] });
  const text = JSON.stringify({ version: 1, bindings: { 'window-machine': ['Ctrl+Alt+g'], save: ['Mod+s'], 'removed-command': ['F12'] } });
  assert.throws(() => registry.loadKeymap(text), /Unknown keymap command: window-machine/);
  const result = registry.loadKeymap(text, { aliases: { 'window-machine': 'window-geometry' }, tolerate: true });
  assert.deepEqual(result.ignored, ['removed-command']);
  assert.deepEqual(registry.keys(registry.commands.get('window-geometry')), ['Ctrl+Alt+g']);
  assert.deepEqual(registry.keys(registry.commands.get('save')), ['Mod+s']);
});
