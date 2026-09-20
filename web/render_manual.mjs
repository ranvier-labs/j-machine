// Renders the in-app manual (site/documentation/topics.js) to docs/manual.md so
// the repository documentation and the workbench share one source.
import { writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { TOPICS } from './site/documentation/topics.js';

const LINKS = {
  doc: href => { const [topic, anchor] = href.split('#'); return `#${topic}${anchor ? `-${anchor}` : ''}`; },
  file: href => `\`${href}\``, command: href => `IDE action \`${href}\``,
};
const inline = text => text.replace(/\[([^\]]+)\]\((doc|file|command):([^)]+)\)/g, (_, label, kind, href) =>
  kind === 'doc' ? `[${label}](${LINKS.doc(href)})` : `${label} (${LINKS[kind](href)})`);
const slug = text => text.toLowerCase().replace(/[^\w]+/g, '-').replace(/^-|-$/g, '');

let out = '# J-Machine workbench manual\n\nGenerated from `web/site/documentation/topics.js` by `npm run docs:render`. Edit the topics file, not this page.\n\n';
out += TOPICS.map(topic => `- [${topic.title}](#${topic.id}): ${topic.summary}`).join('\n') + '\n';
for (const topic of TOPICS) {
  out += `\n<a id="${topic.id}"></a>\n\n## ${topic.title}\n\n${topic.summary}\n`;
  for (const line of topic.body.trim().split('\n')) {
    const heading = line.match(/^## (.*)/);
    out += heading ? `\n<a id="${topic.id}-${slug(heading[1])}"></a>\n\n### ${heading[1]}\n` : `${inline(line)}\n`;
  }
}
await writeFile(new URL('./docs/manual.md', import.meta.url), out);
console.log(`Rendered ${TOPICS.length} topics to ${fileURLToPath(new URL('./docs/manual.md', import.meta.url))}`);
