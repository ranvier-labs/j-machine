import { TOPICS } from './topics.js';
export { TOPICS, CONTEXT_TOPICS } from './topics.js';

export const sectionId = title => title.toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/^-|-$/g, '');
export function blocks(text) {
  const result = [], lines = text.trim().split(/\r?\n/);
  for (let i = 0; i < lines.length;) {
    const line = lines[i];
    if (!line.trim()) { i++; continue; }
    if (line.startsWith('```')) {
      const language = line.slice(3).trim(), code = []; i++;
      while (i < lines.length && !lines[i].startsWith('```')) code.push(lines[i++]);
      i++; result.push({ type: 'code', language, text: code.join('\n') }); continue;
    }
    const heading = line.match(/^## (.+)$/);
    if (heading) { result.push({ type: 'heading', text: heading[1], id: sectionId(heading[1]) }); i++; continue; }
    const list = line.match(/^(- |\d+\. )/);
    if (list) {
      const ordered = list[1] !== '- ', items = [], pattern = ordered ? /^\d+\. (.+)$/ : /^- (.+)$/;
      while (i < lines.length && pattern.test(lines[i])) items.push(lines[i++].replace(pattern, '$1'));
      result.push({ type: 'list', ordered, items }); continue;
    }
    const paragraph = [];
    while (i < lines.length && lines[i].trim() && !/^(## |```|- |\d+\. )/.test(lines[i])) paragraph.push(lines[i++]);
    result.push({ type: 'paragraph', text: paragraph.join(' ') });
  }
  return result;
}
export function inline(text) {
  const result = [], pattern = /`([^`]+)`|\[([^\]]+)\]\(([^)\s]+)\)/g; let cursor = 0;
  for (const match of text.matchAll(pattern)) {
    if (match.index > cursor) result.push({ type: 'text', text: text.slice(cursor, match.index) });
    result.push(match[1] ? { type: 'code', text: match[1] } : { type: 'link', text: match[2], href: match[3] });
    cursor = match.index + match[0].length;
  }
  if (cursor < text.length) result.push({ type: 'text', text: text.slice(cursor) });
  return result;
}
const byId = new Map(TOPICS.map(topic => [topic.id, topic]));
const aliases = { manual: 'welcome', index: 'welcome', help: 'welcome', start: 'quick-start', commands: 'listener', routing: 'geometry', graphics: 'display', builds: 'build' };
export function topicLocation(value = 'welcome') {
  const [query, anchor = ''] = String(value).trim().toLowerCase().split('#');
  const topic = byId.get(aliases[query] ?? query) ?? TOPICS.find(t => t.title.toLowerCase() === query);
  if (!topic || (anchor && !blocks(topic.body).some(block => block.type === 'heading' && block.id === anchor))) return null;
  return { topic: topic.id, anchor };
}
export const topicById = id => byId.get(id);
export function searchTopics(query) {
  const terms = query.toLowerCase().trim().split(/\s+/).filter(Boolean);
  return TOPICS.map((topic, index) => {
    const title = topic.title.toLowerCase(), summary = topic.summary.toLowerCase(), body = topic.body.toLowerCase();
    const score = terms.every(term => (title + ' ' + summary + ' ' + body).includes(term))
      ? terms.reduce((n, term) => n + (title.includes(term) ? 10 : summary.includes(term) ? 4 : 1), 0) : -1;
    return { topic, score, index };
  }).filter(item => item.score >= 0).sort((a, b) => b.score - a.score || a.index - b.index).map(item => item.topic);
}
export function linkTarget(href) {
  if (href.startsWith('doc:')) {
    const location = topicLocation(href.slice(4)); return location && { type: 'documentation', ...location };
  }
  if (/^file:\/[^\s?#]+$/.test(href)) return { type: 'file', path: href.slice(5) };
  if (/^command:[a-z][a-z0-9-]*$/.test(href)) return { type: 'command', command: href.slice(8) };
  if (/^https?:\/\/[^\s]+$/.test(href)) return { type: 'url', href };
  return null;
}
export class ReadingHistory {
  constructor(limit = 64) {
    this.limit = limit; this.entries = [{ topic: 'welcome', anchor: '', scroll: 0 }]; this.index = 0;
    this.positions = new Map();
  }
  get current() { return this.entries[this.index]; }
  get canBack() { return this.index > 0; }
  get canForward() { return this.index < this.entries.length - 1; }
  remember(scroll) {
    this.current.scroll = Math.max(0, Number(scroll) || 0);
    this.positions.set(this.current.topic + '#' + this.current.anchor, this.current.scroll);
  }
  visit(value) {
    const location = topicLocation(value); if (!location) return false;
    if (location.topic === this.current.topic && location.anchor === this.current.anchor) return true;
    this.entries.splice(this.index + 1);
    this.entries.push({ ...location, scroll: this.positions.get(location.topic + '#' + location.anchor) ?? null });
    if (this.entries.length > this.limit) this.entries.shift();
    this.index = this.entries.length - 1; return true;
  }
  move(delta) {
    const next = this.index + delta;
    if (next < 0 || next >= this.entries.length) return false;
    this.index = next; return true;
  }
}

