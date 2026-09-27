// Renders the manual's Markdown subset (paragraphs, ## headings, lists,
// fenced code, `code`, and [links]) into DOM. The link builder decides what a
// link does, so the manual and the tutorial share one renderer.
import { blocks, inline } from './manual.js';
import { element } from '../windows/common.js';

export function prose(node, text, link) {
  for (const part of inline(text)) node.append(part.type === 'link' ? link(part.text, part.href) : part.type === 'code' ? element('code', '', part.text) : document.createTextNode(part.text));
  return node;
}
export function renderMarkdown(container, text, { link, heading = 'h3', onCode } = {}) {
  for (const block of blocks(text)) {
    if (block.type === 'heading') container.append(element(heading, '', block.text));
    else if (block.type === 'paragraph') container.append(prose(element('p'), block.text, link));
    else if (block.type === 'list') {
      const list = element(block.ordered ? 'ol' : 'ul');
      for (const item of block.items) list.append(prose(element('li'), item, link));
      container.append(list);
    } else {
      const pre = element('pre'); pre.append(element('code', '', block.text)); container.append(pre);
      onCode?.(block, container);
    }
  }
  return container;
}
// A link builder for IDE links (doc:, file:, command:) and web URLs.
export function ideLink(ide, { openTopic = topic => ide.services.openDocumentation(topic), describe = () => '' } = {}) {
  return (label, href) => {
    const target = linkTarget(href), node = element('a', '', label);
    if (!target) return document.createTextNode(label);
    if (target.type === 'url') { node.href = target.href; node.target = '_blank'; node.rel = 'noopener'; node.title = target.href; return node; }
    node.href = target.type === 'documentation' ? '?help=' + encodeURIComponent(target.topic + (target.anchor ? '#' + target.anchor : '')) : '#' + href;
    node.title = target.type === 'file' ? 'Open ' + target.path : target.type === 'command' ? 'IDE action: ' + target.command : describe(target) || 'Read ' + target.topic;
    node.onclick = event => {
      event.preventDefault();
      ide.perform(() => {
        if (target.type === 'documentation') openTopic(target.topic + (target.anchor ? '#' + target.anchor : ''));
        else if (target.type === 'file') ide.openFile(target.path);
        else ide.services.command(target.command);
      });
    };
    return node;
  };
}
import { linkTarget } from './manual.js';
