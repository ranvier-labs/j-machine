import { element, button, observe } from './common.js';
import { PORTS, coordinates, nodeAt, dimensions, planeAxes, neighbor, expectedRoute } from '../network/geometry.js';
import { EVENT_NAMES, WAIT_REASONS, packetLabel, linkLabel } from '../network/trace.js';
import { breakpointSpec } from '../network/commands.js';
import { describeWord, wordHex } from '../runtime.js';

const activeTrace = ide => ide.archiveTrace ?? ide.debug?.network;
const act = (ide, action) => () => ide.perform(action);
const notify = ide => { ide.emit('network'); };
const selectPacket = (ide, id) => { const t = activeTrace(ide); t.selectedPacket = id; notify(ide); };
const packetButton = (ide, id) => button(`#${id}`, `Inspect packet ${id}`, () => { selectPacket(ide, id); ide.services.openWindow('packets'); }, 'text-button');
const numberText = n => n == null ? '—' : String(n);
function fields(parent, values) {
  const dl = element('dl', 'inspection-fields');
  for (const [label, value] of values) dl.append(element('dt', '', label), element('dd', '', numberText(value)));
  parent.append(dl);
}
function roving(root, selector, selected, choose) {
  root.addEventListener('keydown', event => {
    if (!['ArrowUp', 'ArrowDown', 'Home', 'End'].includes(event.key) || event.target.matches('input,select,textarea')) return;
    const rows = [...root.querySelectorAll(selector)]; if (!rows.length) return;
    let index = rows.findIndex(row => row.dataset.id === String(selected()));
    index = event.key === 'Home' ? 0 : event.key === 'End' ? rows.length - 1 : Math.max(0, Math.min(rows.length - 1, index + (event.key === 'ArrowDown' ? 1 : -1)));
    event.preventDefault(); const id = rows[index].dataset.id;
    choose(Number(id));
    root.querySelector(`[data-id="${id}"]`)?.focus();
  });
}
export function packetsWindow(ide) {
  const root = element('div', 'network-window'), tools = element('div', 'tool-strip'), filter = element('input');
  filter.ariaLabel = 'Filter packets'; filter.placeholder = 'Filter: src:0 dst:511 priority:0';
  filter.oninput = () => { const t = activeTrace(ide); if (t) { t.filter = filter.value; notify(ide); } };
  const clear = button('All links', 'Clear the selected link filter', () => { const t = activeTrace(ide); if (t) { t.selectedLink = null; notify(ide); } });
  tools.append(filter, clear);
  const status = element('div', 'network-status'), body = element('div', 'packet-body'), list = element('div', 'packet-list'), details = element('div', 'packet-details');
  list.setAttribute('role', 'listbox'); list.ariaLabel = 'Captured packets'; body.append(list, details);
  const bpPanel = element('details', 'network-breakpoints'); bpPanel.open = true;
  bpPanel.append(element('summary', '', 'Network breakpoints'));
  const form = element('form', 'inline-form'), type = element('select'); type.ariaLabel = 'Network breakpoint type';
  type.replaceChildren(...['inject', 'deliver', 'link', 'handler', 'stall'].map(s => new Option(s, s)));
  const predicate = element('input'); predicate.ariaLabel = 'Network breakpoint conditions'; predicate.placeholder = 'dst=511 priority=0';
  const add = element('button', '', 'Add'); form.append(type, predicate, add);
  form.onsubmit = e => { e.preventDefault(); ide.perform(() => ide.addNetworkBreakpoint(breakpointSpec(type.value, predicate.value))); };
  const breakpoints = element('div'); bpPanel.append(form, breakpoints);
  root.append(tools, status, body, bpPanel);
  roving(list, '[data-id]', () => activeTrace(ide)?.selectedPacket, id => selectPacket(ide, id));
  const render = observe(ide, ['network', 'machine', 'state'], () => {
    const t = activeTrace(ide); list.replaceChildren(); details.replaceChildren(); breakpoints.replaceChildren();
    add.disabled = !ide.debug || !!ide.archiveTrace;
    if (!t) { status.textContent = 'Load a machine to capture network events.'; return; }
    if (document.activeElement !== filter) filter.value = t.filter;
    status.textContent = `${t.archived ? 'ARCHIVE' : t.cursor !== null ? 'HISTORY' : 'LIVE'} · ${t.packets.size} packets · ${t.events.length} events · ${t.dropped} dropped · ${t.evicted} older events / ${t.evictedPackets} packets expired${t.selectedLink ? ` · ${linkLabel(t.selectedLink)}` : ''}`;
    const packets = t.visiblePackets(), shown = packets.slice(-500);
    const tabPacket = shown.find(p => p.id === t.selectedPacket) ?? shown[0];
    for (const p of shown) {
      const row = button(`${packetLabel(p)}  ${p.delivered ? `${p.delivered - (p.injected ?? p.sent)} cycles` : 'in flight'}${p.incomplete ? ' · incomplete' : ''}`, `Inspect packet ${p.id}`, () => selectPacket(ide, p.id), 'packet-row');
      row.dataset.id = p.id; row.dataset.focusKey = `packet-${p.id}`; row.setAttribute('role', 'option');
      row.setAttribute('aria-selected', String(p.id === t.selectedPacket)); row.tabIndex = p === tabPacket ? 0 : -1;
      list.append(row);
    }
    if (!list.children.length) list.append(element('p', 'empty-state', 'No matching packets. Run the machine to capture sends.'));
    if (packets.length > 500) list.prepend(element('p', 'empty-state', 'Showing the latest 500 matches. Narrow the filter to find older packets.'));
    const p = t.packetAt(t.selectedPacket);
    if (p) {
      details.append(element('h3', '', packetLabel(p)));
      const actions = element('div', 'tool-strip');
      actions.append(button('Send source', 'Visit the captured send instruction', act(ide, () => ide.visitTraceSource(p.sourceIp))),
        button('Handler', 'Visit the message handler', act(ide, () => ide.visitTraceSource(p.handler))),
        button('Route', 'Show this packet in the mesh', () => ide.services.openWindow('machine')),
        button('History', 'Follow this packet through its causal history', () => ide.services.openWindow('history')));
      details.append(actions);
      fields(details, [['Handler', p.handler == null ? '—' : `0x${p.handler.toString(16)}`], ['Payload words', p.words.length], ['Send / injection', `${p.sent} / ${numberText(p.injected)}`],
        ['First arrival / tail', `${numberText(p.arrived)} / ${numberText(p.delivered)}`], ['Queue admission / complete', `${numberText(p.admitted)} / ${numberText(p.queued)}`],
        ['Handler dispatch', p.dispatched], ['Future resolution', p.resolved], ['Protocol', p.protocol], ['Result', p.result == null ? '—' : describeWord(BigInt(p.result))], ['Stalled buffer cycles', p.stalls], ['Capture', p.incomplete || p.truncated ? 'Partial' : 'Complete so far']]);
      if (p.reply) { const row = element('p', '', 'Reply: '); row.append(packetButton(ide, p.reply)); details.append(row); }
      if (p.replyTo) { const row = element('p', '', 'Resolves request: '); row.append(packetButton(ide, p.replyTo)); details.append(row); }
      if (p.parent) { const row = element('p', '', 'Sent during handler for '); row.append(packetButton(ide, p.parent)); details.append(row); }
      const children = [...t.packets.values()].filter(child => child.parent === p.id);
      if (children.length) { const row = element('p', '', 'Messages sent by this handler: '); children.forEach(child => row.append(packetButton(ide, child.id))); details.append(row); }
      const route = element('div', 'route-hops');
      for (const hop of p.hops) route.append(button(`${linkLabel(hop)} → N${hop.next}`, `Inspect link ${linkLabel(hop)}`, () => { t.selectedLink = { node: hop.node, port: hop.port }; notify(ide); ide.services.openWindow('machine'); }, 'text-button'));
      details.append(element('h4', '', 'Observed hops'), route);
      const words = element('details'), flits = element('details'); words.append(element('summary', '', `Decoded payload (${p.words.length} words)`));
      p.words.forEach((word, i) => words.append(element('div', 'word-row', `${String(i).padStart(3)}  ${wordHex(BigInt(word))}  ${describeWord(BigInt(word))}`)));
      flits.append(element('summary', '', `Raw injection (${p.flits.length} flits)`));
      p.flits.forEach((flit, i) => flits.append(element('div', 'word-row', `${String(i).padStart(3)}  @${flit.cycle}  ${flit.value.toString(16).padStart(5, '0')}${i < 3 ? `  ${'XYZ'[i]} header → ${flit.value & 63}` : ''}${flit.tail ? '  TAIL' : ''}`)));
      details.append(words, flits);
    } else details.append(element('p', 'empty-state', 'Select a packet to inspect its payload and route.'));
    for (const bp of ide.debug?.network.breakpoints.values() ?? []) {
      const row = element('div', 'breakpoint-row'), label = `${bp.id}: ${bp.type} ${Object.entries(bp).filter(([k]) => !['id','type','enabled','lastHit'].includes(k)).map(([k,v]) => `${k}=${v}`).join(' ')}`;
      row.append(button(`${bp.enabled ? '●' : '○'} ${label}`, `Toggle network breakpoint ${bp.id}`, () => { bp.enabled = !bp.enabled; notify(ide); }, 'text-button'),
        button('Remove', `Remove network breakpoint ${bp.id}`, () => { ide.debug.network.breakpoints.delete(bp.id); notify(ide); })); breakpoints.append(row);
    }
  }); render();
  return { id: 'packets', title: 'PACKETS', element: root, onFocus: () => (list.querySelector('[aria-selected=true]') ?? filter).focus(), filter: () => filter.focus() };
}

const svgElement = (name, attrs = {}, text) => { const e = document.createElementNS('http://www.w3.org/2000/svg', name); for (const [k,v] of Object.entries(attrs)) e.setAttribute(k, String(v)); if (text !== undefined) e.textContent = text; return e; };
export function geometryWindow(ide) {
  const root = element('div', 'network-window geometry-window'), tools = element('div', 'tool-strip'), plane = element('select'), mode = element('select'), priority = element('select'), port = element('select');
  plane.ariaLabel = 'Mesh plane'; plane.replaceChildren(...['XY','XZ','YZ'].map(p => new Option(p,p)));
  mode.ariaLabel = 'Geometry view'; mode.replaceChildren(new Option('All slices','slices'),new Option('Selected slice','slice'),new Option('3D overview','iso'));
  priority.ariaLabel = 'Traffic priority'; priority.replaceChildren(new Option('Both priorities','all'),new Option('Priority 0','0'),new Option('Priority 1','1'));
  port.ariaLabel = 'Selected link direction'; port.replaceChildren(...PORTS.slice(1).map((p,i) => new Option(p,String(i+1))));
  const jump = button('Go to node', 'Jump to a node number or x,y,z coordinate', () => ide.services.jumpNode());
  const inspect = button('Inspect link', 'Filter packets by the selected node and link direction', act(ide, () => {
    const t = activeTrace(ide); if (!t) return; if (neighbor(ide.selectedNode, Number(port.value), t.dims) === null) throw new Error('This direction is outside the mesh.');
    t.selectedLink = { node: ide.selectedNode, port: Number(port.value) }; notify(ide); ide.services.openWindow('packets');
  }));
  tools.append(plane,mode,priority,jump,port,inspect);
  const info = element('div', 'network-status'), stage = element('div', 'geometry-stage'); stage.tabIndex = 0; stage.setAttribute('role','grid'); stage.ariaLabel = 'Mesh geometry. Arrow keys move within the plane. Page Up and Page Down change slices. Enter inspects the selected node.';
  const svg = svgElement('svg', { viewBox:'0 0 800 600', 'aria-hidden':'true' }); stage.append(svg);
  const accessible = element('div', 'sr-only'); accessible.id = 'mesh-selection'; stage.append(accessible); stage.setAttribute('aria-describedby', accessible.id);
  const legend = element('div','network-status','Arrows: move · PgUp/PgDn: slice · Enter: inspect · amber: observed packet route · dashed: expected route · red: stalled');
  root.append(tools,info,stage,legend);
  let selected = 0;
  const move = (axis, delta) => {
    const t = activeTrace(ide); if (!t) return;
    const xyz = coordinates(ide.selectedNode < t.nodes ? ide.selectedNode : selected, t.dims); xyz[axis] = Math.max(0,Math.min(t.dims[axis]-1,xyz[axis]+delta));
    selected = nodeAt(xyz,t.dims); if (ide.simulator && selected < ide.simulator.nodes) ide.selectNode(selected); else { ide.selectedNode = selected; notify(ide); }
  };
  stage.onkeydown = e => {
    if (e.ctrlKey || e.metaKey || e.altKey) return;
    const axes = planeAxes(plane.value), directions = { ArrowLeft:[axes[0],-1],ArrowRight:[axes[0],1],ArrowUp:[axes[1],-1],ArrowDown:[axes[1],1],PageUp:[axes[2],-1],PageDown:[axes[2],1] };
    if (directions[e.key]) { e.preventDefault(); move(...directions[e.key]); }
    else if (e.key === 'Enter') { e.preventDefault(); ide.services.openWindow('waiting'); }
  };
  const render = observe(ide,['network','machine','state'],() => {
    const t = activeTrace(ide); svg.replaceChildren();
    if (!t) { info.textContent = 'Load a machine to view its routing geometry.'; return; }
    selected = Math.min(ide.selectedNode,t.nodes-1); const xyz = coordinates(selected,t.dims), axes = planeAxes(plane.value), slice = xyz[axes[2]], p = t.packets.get(t.selectedPacket), state = t.stateAt();
    info.textContent = `${t.mesh.replaceAll('x',' × ')} · N${selected} (${xyz.join(', ')}) · ${'XYZ'[axes[2]]}=${slice} · cycle ${t.cursor ?? t.cycle}${t.cursor !== null ? ' · HISTORY' : ''}`;
    accessible.textContent = info.textContent;
    const slices = mode.value === 'slice' ? [slice] : Array.from({length:t.dims[axes[2]]},(_,i)=>i);
    const cols = slices.length > 1 ? 2 : 1, rows = Math.ceil(slices.length/cols), positions = new Map();
    for (let n=0;n<t.nodes;n++) {
      const c=coordinates(n,t.dims), index=slices.indexOf(c[axes[2]]); if (index<0) continue;
      let x,y;
      if (mode.value==='iso') { x=100+c[0]*40+c[2]*37; y=490-c[1]*45-c[2]*22; }
      else { x=(index%cols)*800/cols+35+(c[axes[0]]+.5)*(800/cols-65)/t.dims[axes[0]]; y=Math.floor(index/cols)*600/rows+25+(c[axes[1]]+.5)*(600/rows-45)/t.dims[axes[1]]; }
      positions.set(n,{x,y});
    }
    if (mode.value!=='iso') slices.forEach((s,i)=>svg.append(svgElement('text',{x:(i%cols)*800/cols+12,y:Math.floor(i/cols)*600/rows+17,class:'slice-label'},`${'XYZ'[axes[2]]} = ${s}`)));
    const drawLink=(node,direction,cls,width=1)=>{
      const next=neighbor(node,direction,t.dims),a=positions.get(node),b=positions.get(next);if(!a)return;
      const end=b??{x:a.x+18,y:a.y+(direction%2?-20:20)};
      const line=svgElement('line',{x1:a.x,y1:a.y,x2:end.x,y2:end.y,class:cls,'stroke-width':width});
      line.style.cursor='pointer';
      line.onclick=()=>{t.selectedLink={node,port:direction};notify(ide);ide.services.openWindow('packets');};
      line.append(svgElement('title',{},`${linkLabel({node,port:direction})} → N${next??'outside slice'}`));svg.append(line);
    };
    for(const n of positions.keys()) for(const axis of axes.slice(0,mode.value==='iso'?3:2)) if(neighbor(n,2+axis*2,t.dims)!==null) drawLink(n,2+axis*2,'mesh-link');
    const traffic=state.links.filter(l=>l.port&&(priority.value==='all'||Number(priority.value)===l.priority));
    for(const l of traffic) if(l.flits) drawLink(l.node,l.port,'traffic-link',Math.min(5,1+Math.log2(l.flits+1)/3));
    if(p?.source!=null&&p.destination!=null) for(const h of expectedRoute(p.source,p.destination,t.dims)) drawLink(h.node,h.port,'expected-link',2);
    for(const h of p?.hops??[]) if(t.cursor===null||h.cycle<=t.cursor) drawLink(h.node,h.port,'packet-link',4);
    for(const w of state.waits) if(priority.value==='all'||Number(priority.value)===w.priority) drawLink(w.node,w.port,'stall-link',4);
    if(t.selectedLink) drawLink(t.selectedLink.node,t.selectedLink.port,'selected-link',6);
    for(const [n,{x,y}]of positions){
      const group=svgElement('g',{class:`mesh-node${n===selected?' selected':''}`});
      group.append(svgElement('circle',{cx:x,cy:y,r:n===selected?8:4}),svgElement('title',{},`Node ${n} (${coordinates(n,t.dims).join(', ')})`));
      if(mode.value==='slice'||t.nodes<=16||n===selected)group.append(svgElement('text',{x:x+9,y:y+4},String(n)));
      group.onclick=()=>{ if(ide.simulator&&n<ide.simulator.nodes)ide.selectNode(n);else{ide.selectedNode=n;notify(ide);} stage.focus(); };svg.append(group);
    }
  });
  for(const control of [plane,mode,priority])control.onchange=render; render();
  return{id:'machine',title:'ROUTING GEOMETRY',element:root,onFocus:()=>stage.focus(),onResize:render,move};
}

export function waitingWindow(ide) {
  const root=element('div','network-window'),tools=element('div','tool-strip'), title=element('strong'), body=element('div','inspection-scroll');
  tools.append(title,button('Go to node','Choose a node to inspect',()=>ide.services.jumpNode()));root.append(tools,body);
  const render=observe(ide,['network','machine','state'],()=>{
    const t=activeTrace(ide),node=ide.selectedNode;body.replaceChildren();title.textContent=`WAITING / NODE ${node}`;
    if(!t){body.append(element('p','empty-state','Load a machine first.'));return;}
    const state=t.stateAt(),cycle=t.cursor??t.cycle;
    body.append(element('h3','','Receive queues'));
    for(const q of state.queues.filter(q=>q.node===node))fields(body,[[`Priority ${q.priority}`,`${q.occupancy}/${q.capacity} words${q.disabled?' · disabled':''}`],['Queue head',`0x${q.head.toString(16)}`]]);
    body.append(element('h3','','Blocked routing inputs'));
    const waits=state.waits.filter(w=>w.node===node);
    if(!waits.length)body.append(element('p','empty-state','No routing stall observed at this cycle.'));
    for(const w of waits){
      const row=element('section','wait-row');row.append(element('p','',`${PORTS[w.input]} → ${PORTS[w.port]} / P${w.priority} · ${WAIT_REASONS[w.reason]} · ${w.duration??1} cycles`));
      if(w.packet)row.append(packetButton(ide,w.packet));
      const next=neighbor(node,w.port,t.dims);
      if(next!==null&&next!==node)row.append(button(`Follow to N${next}`,'Follow this blocked link downstream',()=>{ide.selectedNode=next;if(ide.debug&&next<ide.simulator.nodes)ide.debug.selectedNode=next;notify(ide);}));
      const owner=state.reservations.find(r=>r.node===node&&r.port===w.port&&r.priority===w.priority);
      if(owner?.packet&&owner.packet!==w.packet){row.append(element('span','',' Reserved by '),packetButton(ide,owner.packet));}
      body.append(row);
    }
    body.append(element('h3','','Output reservations'));
    for(const r of state.reservations.filter(r=>r.node===node)){
      const row=element('p','',`${PORTS[r.input]} → ${PORTS[r.port]} / P${r.priority} `);if(r.packet)row.append(packetButton(ide,r.packet));body.append(row);
    }
    body.append(element('h3','','Outstanding remote results'));
    for(const original of t.packets.values()) {
      const p=t.packetAt(original.id,cycle);
      if(p.returnNode!==node||p.returnWords<1||p.sent>cycle||p.resolved)continue;
      const row=element('div','wait-row');row.append(element('p','',`Result mailbox 0x${p.returnAddress.toString(16)} · requested from N${p.destination} · ${p.delivered?'delivered, awaiting reply':'in transit'}`),packetButton(ide,p.id),button('Send source','Visit the call that allocated this future',act(ide,()=>ide.visitTraceSource(p.sourceIp))));body.append(row);
    }
    body.append(element('h3','','Future observations'));
    const future=[...t.futureWaits.values()].filter(f=>f.node===node&&f.cycle<=cycle);
    if(!future.length)body.append(element('p','empty-state','No future fault recorded for this node.'));
    for(const f of future){const row=element('div','wait-row');row.append(element('p','',`${describeWord(BigInt(f.token??f.value))} · fault ${f.aux} at ${f.cycle}${f.resolved&&f.resolved<=cycle?` · resolved at ${f.resolved}`:' · no matching resolution observed'}`),button('Fault source','Visit the instruction that forced this future',act(ide,()=>ide.visitTraceSource(f.ip))));body.append(row);}
    for(const f of [...t.futureWrites.values()].filter(f=>f.node===node&&f.cycle<=cycle).slice(-20))body.append(element('div','word-row',`@${f.cycle} [0x${f.aux.toString(16)}] ${describeWord(BigInt(f.before??0))} → ${describeWord(BigInt(f.value))}`));
    if(t.cursor!==null&&t.evicted)body.prepend(element('p','error-text','Older events expired; historical reservations and queues may be incomplete.'));
  });render();return{id:'waiting',title:'WAITING',element:root,onFocus:()=>tools.querySelector('button').focus()};
}

export function historyWindow(ide) {
  const root=element('div','network-window'),tools=element('div','tool-strip'),status=element('div','network-status'),timeline=element('input'),list=element('div','event-list');
  timeline.type='range';timeline.step='1';timeline.ariaLabel='Inspect trace at cycle';
  const selectEvent=id=>{const t=activeTrace(ide),e=t?.events.find(e=>e.id===id);if(!e)return;t.selectedEvent=e.id;t.cursor=e.cycle;if(e.packet)t.selectedPacket=e.packet;notify(ide);};
  const move=delta=>{const t=activeTrace(ide);if(!t)return;const events=t.events.filter(e=>!t.selectedPacket||e.packet===t.selectedPacket);let index=events.findIndex(e=>e.id===t.selectedEvent);index=Math.max(0,Math.min(events.length-1,index+delta));if(events[index])selectEvent(events[index].id);};
  tools.append(button('Live','Return to the live machine trace',()=>{ide.archiveTrace=null;if(ide.debug)ide.debug.network.cursor=null;notify(ide);}),
    button('Previous event','Inspect the previous event',()=>move(-1)),button('Next event','Inspect the next event',()=>move(1)),
    button('All events','Clear the packet filter in history',()=>{const t=activeTrace(ide);if(t){t.selectedPacket=null;notify(ide);}}),
    button('Save trace','Save captured events with source and build identity',act(ide,()=>ide.services.saveTrace())),
    button('Open trace','Open a saved trace from this computer',()=>ide.services.openTrace()));
  timeline.oninput=()=>{const t=activeTrace(ide);if(t){t.cursor=Number(timeline.value);notify(ide);}};
  list.ariaLabel='Causal event history';list.setAttribute('role','listbox');
  roving(list,'[data-id]',()=>activeTrace(ide)?.selectedEvent,selectEvent);
  root.append(tools,status,timeline,list);
  const render=observe(ide,['network','machine','state'],()=>{
    const t=activeTrace(ide);list.replaceChildren();if(!t){status.textContent='No trace loaded.';return;}
    timeline.min=String(t.events[0]?.cycle??0);timeline.max=String(t.cycle);timeline.value=String(t.cursor??t.cycle);
    status.textContent=`${t.archived?'ARCHIVE':t.cursor!==null?'HISTORY':'LIVE'} · cycle ${t.cursor??t.cycle} / ${t.cycle}${t.selectedPacket?` · packet #${t.selectedPacket}`:''} · ${t.dropped} dropped · ${t.evicted} expired`;
    const events=t.events.filter(e=>!t.selectedPacket||e.packet===t.selectedPacket),index=t.selectedEvent?events.findIndex(e=>e.id===t.selectedEvent):events.length-1;
    const start=Math.max(0,index-60),shown=events.slice(start,start+160),tabEvent=shown.find(e=>e.id===t.selectedEvent)??shown[0];
    for(const e of shown){const row=button(`@${e.cycle}  N${e.node} P${e.priority}  ${EVENT_NAMES[e.kind]}${e.packet?`  #${e.packet}`:''}${e.kind<=5?`  ${PORTS[e.port]}`:''}  ${wordHex(BigInt(e.value))}`,`Inspect event ${e.id} at cycle ${e.cycle}`,()=>selectEvent(e.id),'event-row');row.dataset.id=e.id;row.dataset.focusKey=`event-${e.id}`;row.setAttribute('role','option');row.setAttribute('aria-selected',String(e.id===t.selectedEvent));row.tabIndex=e===tabEvent?0:-1;list.append(row);}
  });render();return{id:'history',title:'CAUSAL HISTORY',element:root,onFocus:()=>timeline.focus(),previous:()=>move(-1),next:()=>move(1)};
}
