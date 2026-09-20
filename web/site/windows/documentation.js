import { element, button } from './common.js';
import { TOPICS, blocks, inline, linkTarget, topicLocation, topicById, searchTopics, ReadingHistory } from '../documentation/manual.js';

export function documentationWindow(ide) {
  const root = element('div', 'documentation-window'), toolbar = element('nav', 'documentation-toolbar');
  toolbar.ariaLabel = 'Documentation navigation';
  const history = new ReadingHistory();
  const article = element('article', 'documentation-page'); article.tabIndex = 0; article.ariaLabel = 'Documentation page';
  const title = element('span', 'documentation-location');
  const remember = () => history.remember(article.scrollTop);
  const travel = delta => { remember(); if (history.move(delta)) render(); };
  const back = button('←', 'Documentation back (Alt Left)', () => travel(-1));
  const forward = button('→', 'Documentation forward (Alt Right)', () => travel(1));
  toolbar.append(back, forward, button('Home', 'Documentation index', () => open('welcome')), title);
  const body = element('div', 'documentation-body'), sidebar = element('aside', 'documentation-index');
  const search = element('input'); search.type = 'search'; search.placeholder = 'Search manual…'; search.ariaLabel = 'Search documentation';
  const count = element('span', 'documentation-count'); count.setAttribute('role', 'status');
  const topics = element('nav', 'documentation-topics'); topics.ariaLabel = 'Documentation topics';
  sidebar.append(search, count, topics); body.append(sidebar, article); root.append(toolbar, body);

  function link(label, href) {
    const target = linkTarget(href), node = element('a', '', label);
    if (!target) return document.createTextNode(label);
    node.href = target.type === 'documentation' ? '?help=' + encodeURIComponent(target.topic + (target.anchor ? '#' + target.anchor : '')) : '#' + href;
    node.title = target.type === 'file' ? 'Open ' + target.path : target.type === 'command' ? 'IDE action: ' + target.command : 'Read ' + topicById(target.topic).title;
    node.onclick = event => {
      event.preventDefault();
      ide.perform(() => {
        if (target.type === 'documentation') open(target.topic + (target.anchor ? '#' + target.anchor : ''));
        else if (target.type === 'file') ide.openFile(target.path);
        else ide.services.command(target.command);
      });
    };
    return node;
  }
  function prose(node, text) {
    for (const part of inline(text)) node.append(part.type === 'link' ? link(part.text, part.href) : part.type === 'code' ? element('code', '', part.text) : document.createTextNode(part.text));
    return node;
  }
  function renderIndex() {
    const matches = searchTopics(search.value);
    count.textContent = search.value.trim() ? matches.length + ' matching topics' : TOPICS.length + ' topics';
    topics.replaceChildren(...matches.map(topic => {
      const node = link(topic.title, 'doc:' + topic.id);
      node.className = 'documentation-topic'; node.title = topic.summary;
      if (history.current.topic === topic.id) node.setAttribute('aria-current', 'page');
      return node;
    }));
    if (!matches.length) topics.append(element('p', 'empty-state', 'No matches. Try fewer words.'));
  }
  function render() {
    const current = history.current, topic = topicById(current.topic), sections = blocks(topic.body);
    title.textContent = topic.title; title.title = topic.id;
    back.disabled = !history.canBack; forward.disabled = !history.canForward;
    article.replaceChildren(element('h2', '', topic.title), element('p', 'documentation-summary', topic.summary));
    const contents = element('nav', 'documentation-contents'); contents.ariaLabel = 'On this page';
    for (const section of sections.filter(block => block.type === 'heading')) contents.append(link(section.text, 'doc:' + topic.id + '#' + section.id));
    article.append(contents);
    for (const block of sections) {
      if (block.type === 'heading') {
        const heading = element('h3', '', block.text); heading.id = 'manual-' + topic.id + '-' + block.id; article.append(heading);
      } else if (block.type === 'paragraph') article.append(prose(element('p'), block.text));
      else if (block.type === 'list') {
        const list = element(block.ordered ? 'ol' : 'ul');
        for (const item of block.items) list.append(prose(element('li'), item));
        article.append(list);
      } else {
        const pre = element('pre'); pre.append(element('code', '', block.text)); article.append(pre);
        if (block.language === 'listener') {
          const commands = element('div', 'documentation-examples');
          for (const line of block.text.split('\n').filter(line => line.trim())) commands.append(button('Insert: ' + line, 'Insert listener command: ' + line, () => ide.services.insertListener(line, true)));
          article.append(commands);
        }
      }
    }
    renderIndex();
    // Scroll only the reader, never the desktop or the neighboring editor.
    const restore = () => {
      if (history.current !== current) return;
      const heading = current.anchor && article.querySelector('#manual-' + current.topic + '-' + current.anchor);
      article.scrollTop = current.scroll ?? (heading ? heading.getBoundingClientRect().top - article.getBoundingClientRect().top + article.scrollTop - 12 : 0);
    };
    restore(); requestAnimationFrame(restore); article.focus({ preventScroll: true });
  }
  function open(value = 'welcome') {
    const location = topicLocation(value);
    if (!location) {
      search.value = value; renderIndex(); search.focus(); search.select(); return;
    }
    remember(); history.visit(location.topic + (location.anchor ? '#' + location.anchor : ''));
    if (location.anchor) history.current.scroll = null;
    render();
  }
  search.oninput = renderIndex;
  search.onkeydown = event => {
    if (event.key === 'Escape') { event.preventDefault(); article.focus(); }
    else if (event.key === 'Enter' || event.key === 'ArrowDown') {
      event.preventDefault(); topics.querySelector('a')?.focus();
    }
  };
  topics.onkeydown = event => {
    if (!['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key)) return;
    const entries = [...topics.querySelectorAll('a')], index = entries.indexOf(document.activeElement);
    if (index < 0) return;
    event.preventDefault();
    const next = event.key === 'Home' ? 0 : event.key === 'End' ? entries.length - 1 : Math.max(0, Math.min(entries.length - 1, index + (event.key === 'ArrowUp' ? -1 : 1)));
    entries[next]?.focus();
  };
  render();
  return { id: 'documentation', title: 'DOCUMENTATION', element: root, open,
    get topic() { return history.current.topic; }, get canBack() { return history.canBack; }, get canForward() { return history.canForward; },
    back: () => travel(-1), forward: () => travel(1), search: () => { search.focus(); search.select(); },
    onFocus: () => article.focus({ preventScroll: true }), onHide: remember };
}
